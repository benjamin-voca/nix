# Composable bootstrap output
# This file composes all bootstrap sub-modules into the final bootstrap output.
# It produces byte-identical output to the original bootstrap.nix.
#
# Module structure:
#   bootstrap/metallb.nix        - MetalLB chart + CRDs
#   bootstrap/ingress-nginx.nix  - Ingress controller
#   bootstrap/argocd.nix         - ArgoCD namespace + chart + forgejo repo
#   bootstrap/rook-ceph.nix      - Rook-Ceph operator + cluster + RGW + backups
#   bootstrap/cnpg.nix           - CloudNativePG operator + cluster
#   bootstrap/forgejo.nix        - Forgejo chart + actions + namespace + PVCs
#   bootstrap/cloudflared.nix    - Cloudflared namespace + configmap + deployment
#   bootstrap/harbor.nix         - Harbor chart + namespace + PVCs + ingress
#   bootstrap/monitoring.nix     - Prometheus + Grafana charts
#   bootstrap/verdaccio.nix      - Verdaccio namespace + PVC + ArgoCD app
#   bootstrap/minecraft.nix      - Minecraft namespace + ArgoCD app
#   bootstrap/erpnext.nix        - ERPNext namespace + helpdesk redirect
#   bootstrap/app-namespaces.nix - EduKurs/BatllavaTourist/QuadPacienti ns + apps
#   bootstrap/orkestr.nix        - Orkestr namespace + CI RBAC
#   bootstrap/openclaw.nix       - OpenClaw (existing)
#   bootstrap/librechat.nix      - LibreChat (existing)
{
  config,
  lib,
  inputs,
  ...
}: let
  shared = import ./bootstrap/shared.nix {inherit lib inputs;};

  systems = shared.systems;
  forAllSystems = shared.forAllSystems;

  # Bootstrap output that merges all sub-modules
  bootstrapFor = system: let
    pkgs = shared.pkgsFor system;
    charts = shared.chartsFor system;
    kubelib = shared.kubelibFor system;
    composable = shared.composableFor system;
    existingCharts = shared.existingChartsFor system;

    # Import all sub-modules
    metallbMod = import ./bootstrap/metallb.nix {inherit pkgs lib charts kubelib composable;};
    ingressNginxMod = import ./bootstrap/ingress-nginx.nix {inherit pkgs lib charts kubelib;};
    argocdMod = import ./bootstrap/argocd.nix {inherit pkgs lib charts kubelib;};
    rookCephMod = import ./bootstrap/rook-ceph.nix {inherit pkgs lib existingCharts;};
    cnpgMod = import ./bootstrap/cnpg.nix {inherit pkgs lib existingCharts;};
    forgejoMod = import ./bootstrap/forgejo.nix {inherit pkgs lib existingCharts;};
    cloudflaredMod = import ./bootstrap/cloudflared.nix {inherit pkgs lib;};
    harborMod = import ./bootstrap/harbor.nix {inherit pkgs lib existingCharts;};
    monitoringMod = import ./bootstrap/monitoring.nix {inherit pkgs lib existingCharts;};
    verdaccioMod = import ./bootstrap/verdaccio.nix {inherit pkgs lib;};
    minecraftMod = import ./bootstrap/minecraft.nix {inherit pkgs lib;};
    erpnextMod = import ./bootstrap/erpnext.nix {inherit pkgs lib;};
    appNamespacesMod = import ./bootstrap/app-namespaces.nix {inherit pkgs lib;};
    orkestrMod = import ./bootstrap/orkestr.nix {inherit pkgs lib;};

    # Existing sub-modules (openclaw, librechat)
    openclawBootstrap = import ./bootstrap/openclaw.nix {inherit lib pkgs;};
    librechatBootstrap = import ./bootstrap/librechat.nix {inherit lib pkgs;};

    # Collect all chart files from all modules
    allChartFiles = {}
      // metallbMod.chartFiles
      // ingressNginxMod.chartFiles
      // argocdMod.chartFiles
      // rookCephMod.chartFiles
      // cnpgMod.chartFiles
      // forgejoMod.chartFiles
      // cloudflaredMod.chartFiles
      // harborMod.chartFiles
      // monitoringMod.chartFiles
      // verdaccioMod.chartFiles
      // minecraftMod.chartFiles
      // erpnextMod.chartFiles
      // appNamespacesMod.chartFiles
      // orkestrMod.chartFiles;

    # Collect all inline files from all modules, converted to Nix store paths
    allInlineFiles = {}
      // metallbMod.inlineFiles
      // ingressNginxMod.inlineFiles
      // argocdMod.inlineFiles
      // rookCephMod.inlineFiles
      // cnpgMod.inlineFiles
      // forgejoMod.inlineFiles
      // cloudflaredMod.inlineFiles
      // harborMod.inlineFiles
      // monitoringMod.inlineFiles
      // verdaccioMod.inlineFiles
      // minecraftMod.inlineFiles
      // erpnextMod.inlineFiles
      // appNamespacesMod.inlineFiles
      // orkestrMod.inlineFiles;

    # Convert inline file strings to Nix store paths
    inlineFileDerivations = lib.mapAttrs (name: content: pkgs.writeText (lib.strings.sanitizeDerivationName name) content) allInlineFiles;

    # Cloudflared config content (special handling for configmap)
    cloudflaredConfigContent = cloudflaredMod.cloudflaredConfigContent;
  in
    pkgs.runCommand "bootstrap-manifests"
    {
      inherit system;
      preferLocalBuild = true;
    }
    ''
      set -euo pipefail

      mkdir -p $out

      # ── Copy chart files ──────────────────────────────────────────────────
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: path: "cp ${path} $out/${name}"
        )
        allChartFiles
      )}

      # ── Copy inline files from Nix store ──────────────────────────────────
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: path: "cp ${path} $out/${name}"
        )
        inlineFileDerivations
      )}

      # ── OpenClaw manifests ────────────────────────────────────────────────
      cp ${openclawBootstrap.manifests."17-openclaw-namespace.yaml"} $out/17-openclaw-namespace.yaml
      cp ${openclawBootstrap.manifests."17a-openclaw-pvc.yaml"} $out/17a-openclaw-pvc.yaml
      cp ${openclawBootstrap.manifests."17b-openclaw-configmap.yaml"} $out/17b-openclaw-configmap.yaml
      cp ${openclawBootstrap.manifests."17c-openclaw-deployment.yaml"} $out/17c-openclaw-deployment.yaml
      cp ${openclawBootstrap.manifests."17d-openclaw-service.yaml"} $out/17d-openclaw-service.yaml
      cp ${openclawBootstrap.manifests."17e-openclaw-ingress.yaml"} $out/17e-openclaw-ingress.yaml

      # ── LibreChat manifests ───────────────────────────────────────────────
      cp ${librechatBootstrap.manifests."19-librechat-namespace.yaml"} $out/19-librechat-namespace.yaml
      cp ${librechatBootstrap.manifests."19a-librechat-configmap.yaml"} $out/19a-librechat-configmap.yaml
      cp ${librechatBootstrap.manifests."19b-librechat-pvc.yaml"} $out/19b-librechat-pvc.yaml
      cp ${librechatBootstrap.manifests."19c-librechat-deployment.yaml"} $out/19c-librechat-deployment.yaml
      cp ${librechatBootstrap.manifests."19d-librechat-service.yaml"} $out/19d-librechat-service.yaml
      cp ${librechatBootstrap.manifests."19e-librechat-ingress.yaml"} $out/19e-librechat-ingress.yaml

      # ── Post-processing: StorageClass filtering ──────────────────────────
      chmod u+w $out/03-rook-ceph-cluster.yaml
      OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
      import os
      import pathlib

      path = pathlib.Path(os.environ["OUT"]) / "03-rook-ceph-cluster.yaml"
      docs = path.read_text().split("\n---\n")
      filtered = []
      for doc in docs:
          content = doc.strip()
          if not content:
              continue
          if "kind: StorageClass" in doc and "name: ceph-filesystem" in doc:
              continue
          filtered.append(content)
      path.write_text("\n---\n".join(filtered) + "\n")
      PY

      # ── Post-processing: Strip last-applied-configuration annotations ────
      OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
      import os
      from pathlib import Path

      target_files = [
          "01b-argocd.yaml",
          "02-rook-ceph.yaml",
          "02a-cnpg-operator.yaml",
          "12-monitoring-chart.yaml",
      ]


      def strip_last_applied_annotation(document: str) -> str:
          if "kind: CustomResourceDefinition" not in document:
              return document

          lines = document.splitlines()
          cleaned = []
          index = 0

          while index < len(lines):
              line = lines[index]
              if "kubectl.kubernetes.io/last-applied-configuration:" in line:
                  indent = len(line) - len(line.lstrip(" "))
                  index += 1

                  while index < len(lines):
                      next_line = lines[index]
                      if next_line.strip() == "":
                          index += 1
                          continue

                      next_indent = len(next_line) - len(next_line.lstrip(" "))
                      if next_indent > indent:
                          index += 1
                          continue

                      break

                  continue

              cleaned.append(line)
              index += 1

          return "\n".join(cleaned)


      out_dir = Path(os.environ["OUT"])
      for name in target_files:
          path = out_dir / name
          if not path.exists():
              continue

          # Files copied into $out are read-only by default.
          path.chmod(0o644)

          docs = path.read_text().split("\n---\n")
          cleaned_docs = []
          for doc in docs:
              if not doc.strip():
                  continue
              cleaned_docs.append(strip_last_applied_annotation(doc.strip()))

          path.write_text("\n---\n".join(cleaned_docs) + "\n")
      PY

      # ── Post-processing: Forgejo service targetPort normalization ────────
      chmod u+w $out/03-forgejo.yaml
      OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
      import os
      from pathlib import Path

      path = Path(os.environ["OUT"]) / "03-forgejo.yaml"
      docs = path.read_text().split("\n---\n")
      updated_docs = []
      for doc in docs:
          if "kind: Service" in doc and "\n  name: forgejo-http\n" in doc:
              doc = doc.replace("targetPort: \n", "targetPort: 3000\n")
          updated_docs.append(doc)
      path.write_text("\n---\n".join(updated_docs) + "\n")
      PY

      # ── Post-processing: Forgejo actions serviceName injection ───────────
      chmod u+w $out/04-forgejo-actions.yaml
      OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
      import os
      from pathlib import Path

      path = Path(os.environ["OUT"]) / "04-forgejo-actions.yaml"
      docs = path.read_text().split("\n---\n")
      updated_docs = []
      for doc in docs:
          if "kind: StatefulSet" in doc and "\n  name: forgejo-actions-act-runner\n" in doc and "serviceName:" not in doc:
              doc = doc.replace(
                  "\nspec:\n  replicas:",
                  "\nspec:\n  serviceName: forgejo-actions-act-runner\n  replicas:",
                  1,
              )
          updated_docs.append(doc)
      path.write_text("\n---\n".join(updated_docs) + "\n")
      PY

      if [ ! -s "$out/04-forgejo-actions.yaml" ]; then
        echo "forgejo-actions chart render is empty; skipping" >&2
        rm -f "$out/04-forgejo-actions.yaml"
      fi

      # ── Special: Cloudflared configmap (JSON content indented into YAML) ─
      cat > $out/05-cloudflared-configmap.yaml << 'CONFIGMAP_EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: cloudflared-config
        namespace: cloudflared
      data:
        config.yaml: |
      CONFIGMAP_EOF
      echo '${cloudflaredConfigContent}' | sed 's/^/    /' >> $out/05-cloudflared-configmap.yaml

      # ── Create combined bootstrap.yaml ───────────────────────────────────
      cat $out/00-metallb.yaml > $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/00-metallb-crds.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/01-ingress-nginx.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/01a-argocd-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/01b-argocd.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02d-rook-ceph-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02-rook-ceph.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/03-rook-ceph-cluster.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02e-ceph-rgw-cnpg-user.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02f-ceph-rgw-cnpg-bucket-job.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02g-edukurs-cnpg-scheduled-backup.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02i-forgejo-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02h-forgejo-cnpg-scheduled-backup.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02a-cnpg-operator.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02b-cnpg-cluster.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/02c-cnpg-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/03-forgejo.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/03a-forgejo-shared-storage-ceph-pvc.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/03b-forgejo-db-storageclass-patch.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/04-forgejo-runner-secret.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      if [ -f "$out/04-forgejo-actions.yaml" ]; then
        cat $out/04-forgejo-actions.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
      fi
      # ArgoCD Forgejo credentials now applied via argocd-deploy service (not in bootstrap)
      cat $out/05-cloudflared-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/05-cloudflared-configmap.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/06-cloudflared-deployment.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/09-harbor-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/09a-harbor-pvcs-ceph.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/10-verdaccio-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/10a-verdaccio-pvc.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/11-harbor-chart.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12-harbor-ingress.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12aa-erpnext-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12a-erpnext-helpdesk-redirect-ingress.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/13-verdaccio-argocd-app.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/11-monitoring-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12-monitoring-chart.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12-grafana-chart.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12a-grafana-ingress.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12b-loki-chart.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12c-promtail-chart.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/12d-orkestr-dashboard.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/11-minecraft-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/14-minecraft-argocd-app.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/15-edukurs-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/15-batllavatourist-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/15-quadpacienti-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/16-edukurs-argocd-app.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/16-batllavatourist-argocd-app.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/16-quadpacienti-argocd-app.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17-openclaw-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17a-openclaw-pvc.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17b-openclaw-configmap.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17c-openclaw-deployment.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17d-openclaw-service.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/17e-openclaw-ingress.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19-librechat-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19a-librechat-configmap.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19b-librechat-pvc.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19c-librechat-deployment.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19d-librechat-service.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/19e-librechat-ingress.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/18-orkestr-namespace.yaml >> $out/bootstrap.yaml
      echo "---" >> $out/bootstrap.yaml
      cat $out/18a-orkestr-ci-rbac.yaml >> $out/bootstrap.yaml
    '';
in {
  config.flake.bootstrap = forAllSystems bootstrapFor;
}
