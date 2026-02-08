{ config, lib, pkgs, ... }:

{
  options.services.quadnix.backbone-services = {
    enable = lib.mkEnableOption "Deploy backbone-only services with HA";
    
    services = lib.mkOption {
      type = lib.types.listOf lib.types.enum [
        "argocd"
        "gitea"
        "grafana"
        "loki"
        "tempo"
        "clickhouse"
        "verdaccio"
      ];
      default = [ "argocd" "gitea" "grafana" "loki" "tempo" "clickhouse" "verdaccio" ];
      description = "List of backbone services to deploy";
    };
    
    giteaRunners = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of Gitea runners to deploy";
    };
  };

  config = lib.mkIf config.services.quadnix.backbone-services.enable {
    # Import all backbone services
    imports = with config.services.quadnix.backbone-services.services; [
      (lib.optionalElem (elem "argocd" this) ../services/argocd-deploy.nix)
      (lib.optionalElem (elem "gitea" this) ../services/gitea-deploy.nix)
      (lib.optionalElem (elem "grafana" this) ../services/grafana-deploy.nix)
      (lib.optionalElem (elem "loki" this) ../services/loki-deploy.nix)
      (lib.optionalElem (elem "tempo" this) ../services/tempo-deploy.nix)
      (lib.optionalElem (elem "clickhouse" this) ../services/clickhouse-deploy.nix)
      (lib.optionalElem (elem "verdaccio" this) ../services/verdaccio-deploy.nix)
    ];

    # Configure node selectors for backbone placement
    _module.args.backboneNodeSelector = {
      "kubernetes.io/hostname" = "backbone-01";
      "role" = "backbone";
    };

    # Configure tolerations for backbone taints
    _module.args.backboneTolerations = [
      { key = "role"; operator = "Equal"; value = "backbone"; effect = "NoSchedule"; }
      { key = "infra"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
    ];

    # Create dedicated namespaces for backbone services
    environment.etc."kubernetes/backbone-namespaces.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: Namespace
      metadata:
        name: argocd
        labels:
          name: argocd
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: gitea
        labels:
          name: gitea
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: grafana
        labels:
          name: grafana
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: loki
        labels:
          name: loki
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: tempo
        labels:
          name: tempo
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: clickhouse
        labels:
          name: clickhouse
          role: backbone
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: verdaccio
        labels:
          name: verdaccio
          role: backbone
    };

    # Create NodePort services for external access
    environment.etc."kubernetes/backbone-services.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: Service
      metadata:
        name: argocd-nodeport
        namespace: argocd
      spec:
        type: NodePort
        ports:
        - port: 80
          targetPort: 8080
          nodePort: 30080
        selector:
          app: argocd-server
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: gitea-nodeport
        namespace: gitea
      spec:
        type: NodePort
        ports:
        - port: 3000
          targetPort: 3000
          nodePort: 30300
        selector:
          app: gitea
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: grafana-nodeport
        namespace: grafana
      spec:
        type: NodePort
        ports:
        - port: 3000
          targetPort: 3000
          nodePort: 30301
        selector:
          app: grafana
    };

    # Create PodDisruptionBudgets for HA
    environment.etc."kubernetes/pod-disruption-budgets.yaml".text = lib.generators.toYAML {} {
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: argocd-pdb
        namespace: argocd
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: argocd-server
      ---
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: gitea-pdb
        namespace: gitea
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: gitea
      ---
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: grafana-pdb
        namespace: grafana
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: grafana
    };

    # Configure resource limits for backbone services
    environment.etc."kubernetes/resource-limits.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: LimitRange
      metadata:
        name: backbone-services-limits
        namespace: argocd
      spec:
        limits:
        - default:
            cpu: "2"
            memory: "4Gi"
          defaultRequest:
            cpu: "500m"
            memory: "1Gi"
          max:
            cpu: "4"
            memory: "8Gi"
          min:
            cpu: "100m"
            memory: "128Mi"
          type: Container
      ---
      apiVersion: v1
      kind: LimitRange
      metadata:
        name: backbone-services-limits
        namespace: gitea
      spec:
        limits:
        - default:
            cpu: "2"
            memory: "4Gi"
          defaultRequest:
            cpu: "500m"
            memory: "1Gi"
          max:
            cpu: "4"
            memory: "8Gi"
          min:
            cpu: "100m"
            memory: "128Mi"
          type: Container
    };

    # Configure Gitea runners with proper distribution
    environment.etc."kubernetes/gitea-runners.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: gitea-runner-config
        namespace: gitea
      data:
        config.yaml: |
          global:
            url: https://gitea.quadtech.dev
            token: ${config.sops.secrets.gitea-runner-token.path}
            work_dir: /home/git/actions-runner/_work
            shutdown_on_idle: false
            idle_timeout: 0
          runners:
            - name: gitea-runner-backbone
              labels:
                - ubuntu-latest
                - linux
                - x86_64
                - self-hosted
                - backbone
              node_selector:
                role: backbone
            - name: gitea-runner-frontline
              labels:
                - ubuntu-latest
                - linux
                - x86_64
                - self-hosted
                - frontline
              node_selector:
                role: frontline
    
    # Create PodDisruptionBudgets for HA
    environment.etc."kubernetes/pod-disruption-budgets.yaml".text = lib.generators.toYAML {} {
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: argocd-pdb
        namespace: argocd
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: argocd-server
      ---
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: gitea-pdb
        namespace: gitea
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: gitea
      ---
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: grafana-pdb
        namespace: grafana
      spec:
        minAvailable: 1
        selector:
          matchLabels:
            app: grafana
    };

    # Configure resource limits for backbone services
    environment.etc."kubernetes/resource-limits.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: LimitRange
      metadata:
        name: backbone-services-limits
        namespace: argocd
      spec:
        limits:
        - default:
            cpu: "1"
            memory: "2Gi"
          defaultRequest:
            cpu: "250m"
            memory: "512Mi"
          max:
            cpu: "2"
            memory: "4Gi"
          min:
            cpu: "50m"
            memory: "128Mi"
          type: Container
      ---
      apiVersion: v1
      kind: LimitRange
      metadata:
        name: backbone-services-limits
        namespace: gitea
      spec:
        limits:
        - default:
            cpu: "1"
            memory: "2Gi"
          defaultRequest:
            cpu: "250m"
            memory: "512Mi"
          max:
            cpu: "2"
            memory: "4Gi"
          min:
            cpu: "50m"
            memory: "128Mi"
          type: Container
    };

    # Create ServiceAccounts for Gitea runners
    environment.etc."kubernetes/gitea-runner-sa.yaml".text = lib.generators.toYAML {} {
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: gitea-runner
        namespace: gitea
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: gitea-runner-role
      rules:
      - apiGroups: [""]
        resources: ["pods", "pods/log"]
        verbs: ["create", "list", "get", "update", "delete"]
      - apiGroups: ["batch"]
        resources: ["jobs"]
        verbs: ["create", "list", "get", "update", "delete"]
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: gitea-runner-binding
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: gitea-runner-role
      subjects:
      - kind: ServiceAccount
        name: gitea-runner
        namespace: gitea
    };
  };
}