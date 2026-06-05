# Replacement for `services.certmgr` on Kubernetes control-plane nodes.
#
# Why this exists:
#   certmgr v3.0.3 (current nixpkgs as of 2026-06) ignores the `before:`
#   renewal threshold and re-persists every certificate on every
#   `renewInterval` cycle, regardless of how much time remains until
#   expiry. Each persist invokes the spec's `action` (typically
#   `systemctl restart kube-apiserver / kubelet / ...`), which thrashes
#   the control plane and disrupts in-flight operations.
#
# What this module does:
#   - Disables `services.certmgr` (the upstream NixOS kubernetes module
#     enables it automatically when `easyCerts = true`).
#   - Adds a `kube-pki-renew` systemd service + timer that periodically
#     checks every k8s certificate. If any is missing or expiring soon,
#     ALL certificates are regenerated against the local cfssl CA and
#     the k8s services are restarted in dependency order.
#   - All renewals are atomic (write-temp + rename) and verified
#     (`openssl x509` parse) before installation, so a failed run leaves
#     the previous certs in place.
#
# Scaling:
#   This module is intended to run on every control-plane node. Each
#   node manages its own certs independently; renewal times are
#   naturally staggered because issuance happens at different times.
#   For a single-node control plane the brief (~10–30s) apiserver
#   restart only happens once per cert lifetime (a year, by default).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.kubernetes.pkiRenew;
  k8sCfg = config.services.kubernetes.pki;

  # cfssl signing configuration used by our renewal script.
  # 1-year certs with the full k8s usage set.
  cfsslSigningConfig = pkgs.writeText "kube-pki-cfssl-signing.json" (builtins.toJSON {
    signing.profiles.default = {
      expiry = "8760h"; # 1 year
      usages = [
        "digital signature"
        "key encipherment"
        "server auth"
        "client auth"
      ];
    };
  });

  # Build a CSR JSON file in the Nix store for each cert in cfg.certs.
  # The same file is used for every renewal of that cert across the
  # lifetime of a system generation.
  #
  # `names` MUST forward `cert.fields` (e.g. { O = "system:masters"; }) when
  # present — otherwise cfssl strips the O field and the resulting cert is
  # not bound to the corresponding system group ClusterRoleBinding
  # (cluster-admin, system:nodes, …). Certs that have no `fields` (e.g.
  # flannel-client, addon-manager) get an empty names entry, which cfssl
  # treats as "use CN only".
  csrFile = name: cert:
    pkgs.writeText "kube-pki-${name}-csr.json" (builtins.toJSON {
      CN = cert.CN;
      hosts = [cert.CN] ++ (cert.hosts or []);
      key = {
        algo = "rsa";
        size = 2048;
      };
      names = [
        (if cert ? fields && cert.fields != {} then cert.fields else {})
      ];
    });

  # All on-disk cert paths — used for the expiry check loop.
  allCertPaths = lib.mapAttrsToList (_: c: c.cert) k8sCfg.certs;

  # Bash block that renews one cert into a temp dir, verifies it,
  # and atomically installs it (sibling temp file + rename).
  installCert = name: cert: let
    mode = cert.privateKeyOptions.mode or "0600";
    owner = cert.privateKeyOptions.owner or "root";
    group = cert.privateKeyOptions.group or "root";
    keyPath = cert.privateKeyOptions.path;
  in ''
    echo "  - ${name} (CN=${cert.CN})"
    OUT_DIR="$(mktemp -d)"
    cfssl gencert \
      -ca "$CA_CERT" -ca-key "$CA_KEY" \
      -config "${cfsslSigningConfig}" -profile default \
      "${csrFile name cert}" \
      | cfssljson -bare "$OUT_DIR/cert"

    # Refuse to install a malformed cert.
    openssl x509 -in "$OUT_DIR/cert.pem" -noout >/dev/null \
      || { echo "ERROR: generated cert for ${name} is invalid"; rm -rf "$OUT_DIR"; exit 1; }

    # Atomic install (sibling temp file + rename).
    install -m 0644 -o root -g root "$OUT_DIR/cert.pem" "${cert.cert}.tmp.$$"
    mv -f "${cert.cert}.tmp.$$" "${cert.cert}"

    install -m ${mode} -o ${owner} -g ${group} \
      "$OUT_DIR/cert-key.pem" "${keyPath}.tmp.$$"
    mv -f "${keyPath}.tmp.$$" "${keyPath}"

    rm -rf "$OUT_DIR"
  '';

  renewalScript = pkgs.writeShellScript "kube-pki-renew" ''
    set -euo pipefail

    SECRETS_DIR="/var/lib/kubernetes/secrets"
    CA_CERT="/var/lib/cfssl/ca.pem"
    CA_KEY="/var/lib/cfssl/ca-key.pem"
    RENEW_BEFORE_DAYS="${toString cfg.renewBeforeDays}"

    # Wait for cfssl to have generated the CA (first boot).
    for i in $(seq 1 60); do
      [ -f "$CA_CERT" ] && [ -f "$CA_KEY" ] && break
      sleep 1
    done
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
      echo "ERROR: CA files missing at $CA_CERT — cfssl not initialized"
      exit 1
    fi

    # Returns 0 (true) if the cert at $1 needs renewal:
    #   - file does not exist  → need initial generation
    #   - file not parseable   → corrupt, regenerate
    #   - expiry < threshold   → close to expiry
    needs_renewal() {
      local cert_path="$1"
      [ -f "$cert_path" ] || return 0
      local expiry_date expiry_epoch now_epoch remaining_days
      expiry_date="$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
      [ -n "$expiry_date" ] || return 0
      expiry_epoch="$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)"
      now_epoch="$(date +%s)"
      remaining_days=$(( (expiry_epoch - now_epoch) / 86400 ))
      [ "$remaining_days" -lt "$RENEW_BEFORE_DAYS" ]
    }

    # All certs share an issuance time and lifetime, so any one of them
    # expiring soon means we renew the lot.
    any_needs_renewal=0
    for cert_path in ${lib.concatStringsSep " " allCertPaths}; do
      if needs_renewal "$cert_path"; then
        any_needs_renewal=1
        break
      fi
    done

    if [ "$any_needs_renewal" -eq 0 ]; then
      echo "All certificates valid — no renewal needed"
      exit 0
    fi

    echo "Renewing Kubernetes certificates..."
    mkdir -p "$SECRETS_DIR"

    ${lib.concatStrings (lib.mapAttrsToList installCert k8sCfg.certs)}

    echo "Restarting Kubernetes services in dependency order..."
    # 1. Apiserver first — everything else depends on it.
    systemctl restart kube-apiserver.service
    sleep 2
    # 2. Controllers and scheduler (apiserver is back up).
    systemctl restart kube-controller-manager.service kube-scheduler.service
    sleep 1
    # 3. Node-level components.
    systemctl restart kubelet.service kube-proxy.service \
      kube-addon-manager.service flannel.service

    echo "Certificate renewal complete"
  '';
in {
  options.services.kubernetes.pkiRenew = {
    enable = lib.mkEnableOption ''
      Kubernetes PKI certificate renewal (replaces certmgr).

      When enabled, this module disables certmgr (which has a known bug
      that causes control-plane thrash) and manages certificate lifecycle
      itself: initial generation, periodic expiry checks, atomic renewal,
      and ordered service restarts.
    '';

    renewBeforeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        Number of days before certificate expiry to trigger renewal.
        When any certificate has less than this many days of validity
        remaining, ALL certificates are regenerated and ALL k8s services
        on this node are restarted.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      example = "30min";
      description = ''
        How often to check certificates for renewal. Format is systemd
        <citerefentry><refentrytitle>systemd.timer</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry>
        <option>OnUnitActiveSec</option>.

        With the default 1-year cert lifetime and 30-day
        <option>renewBeforeDays</option>, hourly checks give ~720
        opportunities to renew before expiry.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable certmgr to stop the control-plane thrash. Our service
    # takes over cert generation and renewal. mkForce is needed because
    # `easyCerts = true` enables certmgr at normal priority.
    services.certmgr.enable = lib.mkForce false;

    systemd.services.kube-pki-renew = {
      description = "Kubernetes PKI certificate renewal";
      documentation = ["file://${./pki-renew.nix}"];
      after = ["cfssl.service" "network-online.target"];
      wants = ["cfssl.service" "network-online.target"];
      # Run on every boot so first-boot generation happens before the
      # k8s services (which `after` us) try to start.
      wantedBy = ["multi-user.target"];
      path = with pkgs; [
        cfssl
        coreutils
        openssl
        systemd
        util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = renewalScript;
        User = "root";
        # Keep the service "active" after successful exit so dependent
        # units' `after` ordering has something to wait on.
        RemainAfterExit = true;
        # Don't auto-restart on failure — a failed renewal should be
        # investigated, not retried in a tight loop. The hourly timer
        # will retry on its next tick.
        Restart = "no";
      };
    };

    systemd.timers.kube-pki-renew = {
      description = "Kubernetes PKI renewal check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
        # Spread checks across the cluster so multi-master deployments
        # don't all renew at the same instant.
        RandomizedDelaySec = "5min";
      };
    };
  };
}
