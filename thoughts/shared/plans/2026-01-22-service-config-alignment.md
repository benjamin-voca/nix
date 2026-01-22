# Service Configuration Alignment Implementation Plan

**Goal:** Align Kubernetes control-plane and Gitea service configuration with NixOS modules, replacing ad-hoc config files with declarative module options and generated config artifacts.

**Architecture:** Implement a layered Nix module stack under `nix/modules/` with shared defaults and service-specific modules. Control-plane and Gitea modules generate `/etc` config files and systemd units from module options, while profiles/services import these modules and set environment-specific values. Design requires “control-plane” naming; this is implemented as `services.kubernetes.controlPlane` to match existing NixOS conventions and avoid invalid attribute names.

**Design:** `thoughts/shared/designs/2026-01-22-service-config-alignment-design.md`

---

## Dependency Graph

```
Batch 1 (parallel): 1.1, 1.2, 1.3 [foundation - no deps]
Batch 2 (parallel): 2.1, 2.2 [core - depends on batch 1]
Batch 3 (parallel): 3.1, 3.2 [core - depends on batch 1]
Batch 4 (parallel): 4.1, 4.2, 4.3 [integration - depends on batches 1-3]
```

---

## Batch 1: Foundation (parallel - 3 implementers)

All tasks in this batch have NO dependencies and run simultaneously.

### Task 1.1: Shared environment defaults
**File:** `nix/modules/shared/common.nix`
**Test:** `tests/nix/shared/common.test.nix`
**Depends:** none

```nix
{ config, lib, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.quadnix;
in {
  options.quadnix = {
    environment = mkOption {
      type = types.enum [ "dev" "staging" "prod" ];
      default = "prod";
      description = "Deployment environment label.";
    };

    versions = {
      kubernetes = mkOption {
        type = types.str;
        default = "1.29.3";
        description = "Pinned Kubernetes version for control-plane/worker.";
      };
      gitea = mkOption {
        type = types.str;
        default = "1.21.5";
        description = "Pinned Gitea version for server/runner.";
      };
    };

    paths = {
      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/quadnix";
        description = "Base state directory for QuadNix-managed services.";
      };
      configDir = mkOption {
        type = types.str;
        default = "/etc/quadnix";
        description = "Base config directory for QuadNix-managed services.";
      };
    };
  };

  config = {
    environment.etc."quadnix/environment".text = cfg.environment;
    environment.etc."quadnix/versions.json".text = builtins.toJSON cfg.versions;
    environment.etc."quadnix/paths.json".text = builtins.toJSON cfg.paths;
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      {
        quadnix.environment = "staging";
        quadnix.versions.kubernetes = "1.28.1";
        quadnix.paths.stateDir = "/data/quadnix";
      }
    ];
  };

  envText = lib.attrByPath [ "environment" "etc" "quadnix/environment" "text" ] null eval.config;
  versionsText = lib.attrByPath [ "environment" "etc" "quadnix/versions.json" "text" ] null eval.config;
in
assert envText == "staging";
assert versionsText != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/shared/common.test.nix`
**Commit:** `feat(modules): add shared quadnix defaults`

### Task 1.2: Shared Kubernetes defaults
**File:** `nix/modules/shared/kubernetes-common.nix`
**Test:** `tests/nix/shared/kubernetes-common.test.nix`
**Depends:** 1.1 (uses quadnix version defaults)

```nix
{ config, lib, ... }:

let
  inherit (lib) mkOption mkIf types;
  cfg = config.services.kubernetes.common;
in {
  options.services.kubernetes.common = {
    clusterName = mkOption {
      type = types.str;
      default = "quadnix";
      description = "Logical cluster name for Kubernetes components.";
    };

    serviceCIDR = mkOption {
      type = types.str;
      default = "10.96.0.0/12";
      description = "Service CIDR for Kubernetes services.";
    };

    podCIDR = mkOption {
      type = types.str;
      default = "10.244.0.0/16";
      description = "Pod CIDR for cluster networking.";
    };

    pkiDir = mkOption {
      type = types.str;
      default = "/var/lib/kubernetes/pki";
      description = "PKI directory for Kubernetes certificates.";
    };

    version = mkOption {
      type = types.str;
      default = config.quadnix.versions.kubernetes;
      description = "Pinned Kubernetes version for the cluster.";
    };
  };

  config = mkIf (config.services.kubernetes.enable or false) {
    environment.etc."kubernetes/common.json".text = builtins.toJSON {
      inherit (cfg) clusterName serviceCIDR podCIDR pkiDir version;
    };
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/kubernetes-common.nix
      {
        services.kubernetes.enable = true;
        services.kubernetes.common.clusterName = "alpha";
      }
    ];
  };

  commonText = lib.attrByPath [ "environment" "etc" "kubernetes/common.json" "text" ] null eval.config;
in
assert commonText != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/shared/kubernetes-common.test.nix`
**Commit:** `feat(modules): add shared kubernetes defaults`

### Task 1.3: Shared Gitea defaults
**File:** `nix/modules/shared/gitea-common.nix`
**Test:** `tests/nix/shared/gitea-common.test.nix`
**Depends:** 1.1 (uses quadnix version defaults)

```nix
{ config, lib, ... }:

let
  inherit (lib) mkOption mkIf types;
  cfg = config.services.gitea.common;
in {
  options.services.gitea.common = {
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea";
      description = "Gitea state directory.";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/gitea";
      description = "Gitea config directory.";
    };

    user = mkOption {
      type = types.str;
      default = "gitea";
      description = "Gitea service user.";
    };

    group = mkOption {
      type = types.str;
      default = "gitea";
      description = "Gitea service group.";
    };

    version = mkOption {
      type = types.str;
      default = config.quadnix.versions.gitea;
      description = "Pinned Gitea version for the server.";
    };
  };

  config = mkIf (config.services.gitea.enable or false) {
    environment.etc."gitea/conf/common.json".text = builtins.toJSON {
      inherit (cfg) stateDir configDir user group version;
    };
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/gitea-common.nix
      {
        services.gitea.enable = true;
        services.gitea.common.stateDir = "/data/gitea";
      }
    ];
  };

  commonText = lib.attrByPath [ "environment" "etc" "gitea/conf/common.json" "text" ] null eval.config;
in
assert commonText != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/shared/gitea-common.test.nix`
**Commit:** `feat(modules): add shared gitea defaults`

---

## Batch 2: Kubernetes Modules (parallel - 2 implementers)

All tasks in this batch depend on Batch 1 completing.

### Task 2.1: Kubernetes control-plane module
**File:** `nix/modules/kubernetes/control-plane.nix`
**Test:** `tests/nix/kubernetes/control-plane.test.nix`
**Depends:** 1.2 (uses kubernetes common defaults)

```nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.kubernetes.controlPlane;
  yaml = pkgs.formats.yaml { };
in {
  options.services.kubernetes.controlPlane = {
    enable = mkEnableOption "Kubernetes control-plane";

    version = mkOption {
      type = types.str;
      default = config.services.kubernetes.common.version;
      description = "Pinned Kubernetes version for control-plane nodes.";
    };

    etcd = {
      enable = mkEnableOption "etcd";
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/etcd";
      };
      cluster = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      listenClientUrls = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2379" ];
      };
      listenPeerUrls = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2380" ];
      };
      initialClusterState = mkOption {
        type = types.enum [ "new" "existing" ];
        default = "new";
      };
    };

    apiServer = {
      enable = mkEnableOption "API server";
      advertiseAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
      };
      bindPort = mkOption {
        type = types.int;
        default = 6443;
      };
      etcdServers = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2379" ];
      };
      authorizationModes = mkOption {
        type = types.listOf types.str;
        default = [ "Node" "RBAC" ];
      };
    };

    scheduler = {
      enable = mkEnableOption "Scheduler";
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      leaderElect = mkOption {
        type = types.bool;
        default = true;
      };
    };

    controllerManager = {
      enable = mkEnableOption "Controller manager";
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      clusterCIDR = mkOption {
        type = types.str;
        default = config.services.kubernetes.common.podCIDR;
      };
      serviceCIDR = mkOption {
        type = types.str;
        default = config.services.kubernetes.common.serviceCIDR;
      };
      leaderElect = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."kubernetes/control-plane-version".text = cfg.version;

    environment.etc."kubernetes/etcd.conf".source = mkIf cfg.etcd.enable (
      yaml.generate "etcd.conf" {
        name = config.networking.hostName or "control-plane";
        "data-dir" = cfg.etcd.dataDir;
        "listen-client-urls" = cfg.etcd.listenClientUrls;
        "listen-peer-urls" = cfg.etcd.listenPeerUrls;
        "initial-cluster" = cfg.etcd.cluster;
        "initial-cluster-state" = cfg.etcd.initialClusterState;
      }
    );

    environment.etc."kubernetes/api-server.yaml".source = mkIf cfg.apiServer.enable (
      yaml.generate "api-server.yaml" {
        "advertise-address" = cfg.apiServer.advertiseAddress;
        "bind-port" = cfg.apiServer.bindPort;
        "etcd-servers" = cfg.apiServer.etcdServers;
        "authorization-mode" = cfg.apiServer.authorizationModes;
      }
    );

    environment.etc."kubernetes/scheduler.yaml".source = mkIf cfg.scheduler.enable (
      yaml.generate "scheduler.yaml" {
        "bind-address" = cfg.scheduler.bindAddress;
        "leader-elect" = cfg.scheduler.leaderElect;
      }
    );

    environment.etc."kubernetes/controller-manager.yaml".source = mkIf cfg.controllerManager.enable (
      yaml.generate "controller-manager.yaml" {
        "bind-address" = cfg.controllerManager.bindAddress;
        "cluster-cidr" = cfg.controllerManager.clusterCIDR;
        "service-cluster-ip-range" = cfg.controllerManager.serviceCIDR;
        "leader-elect" = cfg.controllerManager.leaderElect;
      }
    );
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/kubernetes-common.nix
      ../../nix/modules/kubernetes/control-plane.nix
      {
        services.kubernetes.enable = true;
        services.kubernetes.controlPlane.enable = true;
        services.kubernetes.controlPlane.etcd.enable = true;
        services.kubernetes.controlPlane.apiServer.enable = true;
        services.kubernetes.controlPlane.apiServer.advertiseAddress = "10.0.0.1";
        services.kubernetes.controlPlane.etcd.cluster = [ "https://etcd-0:2379" ];
      }
    ];
  };

  apiServer = lib.attrByPath [ "environment" "etc" "kubernetes/api-server.yaml" "source" ] null eval.config;
  etcdConf = lib.attrByPath [ "environment" "etc" "kubernetes/etcd.conf" "source" ] null eval.config;
in
assert apiServer != null;
assert etcdConf != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/kubernetes/control-plane.test.nix`
**Commit:** `feat(kubernetes): add control-plane module`

### Task 2.2: Kubernetes worker module
**File:** `nix/modules/kubernetes/worker.nix`
**Test:** `tests/nix/kubernetes/worker.test.nix`
**Depends:** 1.2 (uses kubernetes common defaults)

```nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.kubernetes.worker;
  yaml = pkgs.formats.yaml { };
in {
  options.services.kubernetes.worker = {
    enable = mkEnableOption "Kubernetes worker";

    nodeIP = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };

    clusterDNS = mkOption {
      type = types.listOf types.str;
      default = [ "10.96.0.10" ];
    };

    clusterDomain = mkOption {
      type = types.str;
      default = "cluster.local";
    };

    cgroupDriver = mkOption {
      type = types.enum [ "systemd" "cgroupfs" ];
      default = "systemd";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = mkIf cfg.enable {
    environment.etc."kubernetes/kubelet.yaml".source = yaml.generate "kubelet.yaml" {
      "node-ip" = cfg.nodeIP;
      "cluster-dns" = cfg.clusterDNS;
      "cluster-domain" = cfg.clusterDomain;
      "cgroup-driver" = cfg.cgroupDriver;
      "extra-args" = cfg.extraArgs;
    };
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/kubernetes-common.nix
      ../../nix/modules/kubernetes/worker.nix
      {
        services.kubernetes.worker.enable = true;
        services.kubernetes.worker.nodeIP = "10.1.0.5";
      }
    ];
  };

  kubeletConfig = lib.attrByPath [ "environment" "etc" "kubernetes/kubelet.yaml" "source" ] null eval.config;
in
assert kubeletConfig != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/kubernetes/worker.test.nix`
**Commit:** `feat(kubernetes): add worker module`

---

## Batch 3: Gitea Modules (parallel - 2 implementers)

All tasks in this batch depend on Batch 1 completing.

### Task 3.1: Gitea server enhancements
**File:** `nix/modules/gitea/server.nix`
**Test:** `tests/nix/gitea/server.test.nix`
**Depends:** 1.3 (uses gitea common defaults)

```nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.gitea;
  ini = pkgs.formats.ini { };
  giteaUser = lib.attrByPath [ "services" "gitea" "user" ] "gitea" config;
  giteaPkg = lib.attrByPath [ "services" "gitea" "package" ] pkgs.gitea config;

  dbConfig = {
    database = {
      DB_TYPE = cfg.database.type;
      HOST = cfg.database.host;
      PORT = cfg.database.port;
      NAME = cfg.database.name;
      USER = cfg.database.user;
      PASSWD = if cfg.database.passwordFile == null
        then ""
        else builtins.readFile cfg.database.passwordFile;
      SSL_MODE = cfg.database.sslMode;
    };
  };

  sshConfig = {
    ssh = {
      ENABLE_SSH = cfg.ssh.enable;
      SSH_LISTEN_PORT = cfg.ssh.port;
      SSH_LISTEN_HOST = cfg.ssh.listenHost;
      SSH_AUTHORIZED_KEYS_ONLY = cfg.ssh.authorizedKeysOnly;
    };
  };

  backupScript = pkgs.writeShellScript "gitea-backup" ''
    set -euo pipefail
    backup_dir="${cfg.backup.targetDir}"
    timestamp="$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    ${giteaPkg}/bin/gitea dump --file "$backup_dir/gitea-$timestamp.zip"
    ${pkgs.findutils}/bin/find "$backup_dir" -type f -name "gitea-*.zip" -mtime +${toString cfg.backup.retention} -delete
  '';

  migrateScript = pkgs.writeShellScript "gitea-migrate" ''
    set -euo pipefail
    ${giteaPkg}/bin/gitea migrate ${lib.concatStringsSep " " cfg.migrations.extraArgs}
  '';
in {
  options.services.gitea = {
    database = {
      type = mkOption {
        type = types.enum [ "postgres" "mysql" "sqlite3" ];
        default = "postgres";
      };
      host = mkOption { type = types.str; default = "localhost"; };
      port = mkOption { type = types.int; default = 5432; };
      name = mkOption { type = types.str; default = "gitea"; };
      user = mkOption { type = types.str; default = "gitea"; };
      passwordFile = mkOption { type = types.nullOr types.path; default = null; };
      sslMode = mkOption { type = types.str; default = "disable"; };
    };

    ssh = {
      enable = mkEnableOption "Gitea SSH";
      port = mkOption { type = types.port; default = 22; };
      listenHost = mkOption { type = types.str; default = "0.0.0.0"; };
      authorizedKeysOnly = mkOption { type = types.bool; default = true; };
    };

    backup = {
      enable = mkEnableOption "Gitea backups";
      interval = mkOption { type = types.str; default = "daily"; };
      retention = mkOption { type = types.int; default = 30; };
      targetDir = mkOption { type = types.str; default = "/var/backups/gitea"; };
    };

    migrations = {
      enable = mkEnableOption "Gitea database migrations";
      extraArgs = mkOption { type = types.listOf types.str; default = []; };
    };
  };

  config = mkIf (cfg.enable or false) {
    environment.etc."gitea/conf/database.ini".source = ini.generate "database.ini" dbConfig;
    environment.etc."gitea/conf/ssh.conf".source = ini.generate "ssh.conf" sshConfig;
    environment.etc."gitea/conf/version".text = config.services.gitea.common.version;

    systemd.services.gitea-migrate = mkIf cfg.migrations.enable {
      description = "Run Gitea database migrations";
      before = [ "gitea.service" ];
      requiredBy = [ "gitea.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = giteaUser;
      };
      script = migrateScript;
    };

    systemd.services.gitea-backup = mkIf cfg.backup.enable {
      description = "Gitea backup job";
      serviceConfig = {
        Type = "oneshot";
        User = giteaUser;
      };
      script = backupScript;
    };

    systemd.timers.gitea-backup = mkIf cfg.backup.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.interval;
        Persistent = true;
      };
    };
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/gitea-common.nix
      ../../nix/modules/gitea/server.nix
      {
        services.gitea.enable = true;
        services.gitea.database.host = "db.internal";
        services.gitea.ssh.enable = true;
        services.gitea.backup.enable = true;
        services.gitea.migrations.enable = true;
      }
    ];
  };

  dbIni = lib.attrByPath [ "environment" "etc" "gitea/conf/database.ini" "source" ] null eval.config;
  backupTimer = lib.attrByPath [ "systemd" "timers" "gitea-backup" "timerConfig" "OnCalendar" ] null eval.config;
in
assert dbIni != null;
assert backupTimer == "daily";
true
```

**Verify:** `nix-instantiate --eval tests/nix/gitea/server.test.nix`
**Commit:** `feat(gitea): add server config extensions`

### Task 3.2: Gitea runner module
**File:** `nix/modules/gitea/runner.nix`
**Test:** `tests/nix/gitea/runner.test.nix`
**Depends:** 1.3 (uses gitea common defaults)

```nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.gitea.runner;
  yaml = pkgs.formats.yaml { };
  runnerPkg = cfg.package;
in {
  options.services.gitea.runner = {
    enable = mkEnableOption "Gitea actions runner";

    package = mkOption {
      type = types.package;
      default = pkgs.gitea-actions-runner;
      description = "Runner package to execute workflows.";
    };

    registrationUrl = mkOption {
      type = types.str;
      default = "https://git.quadtech.dev";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "Path to the runner registration token file.";
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [ "linux" "x86_64" ];
    };

    instanceName = mkOption {
      type = types.str;
      default = "quadnix-runner";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea-runner";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."gitea/runner/config.yaml".source = yaml.generate "gitea-runner.yaml" {
      runner = {
        name = cfg.instanceName;
        labels = cfg.labels;
        token = "${builtins.readFile cfg.tokenFile}";
        url = cfg.registrationUrl;
        state_dir = cfg.stateDir;
      };
    };

    systemd.services.gitea-runner = {
      description = "Gitea actions runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${runnerPkg}/bin/act_runner daemon --config /etc/gitea/runner/config.yaml";
        Restart = "always";
        StateDirectory = "gitea-runner";
      };
    };
  };
}
```

```nix
{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/gitea-common.nix
      ../../nix/modules/gitea/runner.nix
      {
        services.gitea.runner.enable = true;
        services.gitea.runner.tokenFile = builtins.toFile "token" "runner-token";
      }
    ];
  };

  runnerConfig = lib.attrByPath [ "environment" "etc" "gitea/runner/config.yaml" "source" ] null eval.config;
  runnerService = lib.attrByPath [ "systemd" "services" "gitea-runner" "serviceConfig" "ExecStart" ] null eval.config;
in
assert runnerConfig != null;
assert runnerService != null;
true
```

**Verify:** `nix-instantiate --eval tests/nix/gitea/runner.test.nix`
**Commit:** `feat(gitea): add runner module`

---

## Batch 4: Integration Updates (parallel - 3 implementers)

All tasks in this batch depend on Batches 1-3 completing.

### Task 4.1: Control-plane profile alignment
**File:** `profiles/kubernetes/control-plane.nix`
**Test:** none (profile config)
**Depends:** 2.1

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../../nix/modules/shared/common.nix
    ../../nix/modules/shared/kubernetes-common.nix
    ../../nix/modules/kubernetes/control-plane.nix
  ];

  services.kubernetes.enable = true;
  services.kubernetes.controlPlane = {
    enable = true;
    etcd.enable = true;
    apiServer.enable = true;
    scheduler.enable = true;
    controllerManager.enable = true;
  };
}
```

**Verify:** `nix-instantiate --eval profiles/kubernetes/control-plane.nix`
**Commit:** `chore(profiles): align control-plane profile`

### Task 4.2: Worker profile alignment
**File:** `profiles/kubernetes/worker.nix`
**Test:** none (profile config)
**Depends:** 2.2

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../../nix/modules/shared/common.nix
    ../../nix/modules/shared/kubernetes-common.nix
    ../../nix/modules/kubernetes/worker.nix
  ];

  services.kubernetes.enable = true;
  services.kubernetes.worker.enable = true;
}
```

**Verify:** `nix-instantiate --eval profiles/kubernetes/worker.nix`
**Commit:** `chore(profiles): align worker profile`

### Task 4.3: Gitea service alignment
**File:** `services/gitea.nix`
**Test:** none (service config)
**Depends:** 3.1

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../nix/modules/shared/common.nix
    ../nix/modules/shared/gitea-common.nix
    ../nix/modules/gitea/server.nix
  ];

  services.gitea = {
    enable = true;
    database = {
      type = "postgres";
      host = "postgres.quadtech.dev";
      name = "gitea";
      user = "gitea";
    };
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeysOnly = true;
    };
    backup = {
      enable = true;
      interval = "daily";
      retention = 30;
    };
    migrations.enable = true;
    domain = "git.quadtech.dev";
    rootUrl = "https://git.quadtech.dev";
  };
}
```

**Verify:** `nix-instantiate --eval services/gitea.nix`
**Commit:** `chore(services): align gitea service config`
