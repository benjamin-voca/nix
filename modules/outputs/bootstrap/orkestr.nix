# Orkestr bootstrap module
# Orkestr namespace + CI RBAC
{
  pkgs,
  lib,
}: let
  orkestrNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: orkestr
      labels:
        app.kubernetes.io/name: orkestr
  '';

  orkestrCiRbac = ''
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: gitea-ci
      namespace: orkestr
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: orkestr-ci-deployer
      namespace: orkestr
    rules:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: [""]
        resources: ["services", "configmaps", "secrets", "pods"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: ["networking.k8s.io"]
        resources: ["ingresses"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: ["postgresql.cnpg.io"]
        resources: ["clusters", "databases"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: [""]
        resources: ["persistentvolumeclaims"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: gitea-ci-deployer
      namespace: orkestr
    subjects:
      - kind: ServiceAccount
        name: gitea-ci
        namespace: orkestr
    roleRef:
      kind: Role
      name: orkestr-ci-deployer
      apiGroup: rbac.authorization.k8s.io
    ---
    # Long-lived API token for CI kubeconfig
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitea-ci-token
      namespace: orkestr
      annotations:
        kubernetes.io/service-account.name: gitea-ci
    type: kubernetes.io/service-account-token
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "18-orkestr-namespace.yaml" = orkestrNamespace;
    "18a-orkestr-ci-rbac.yaml" = orkestrCiRbac;
  };

  order = [
    "18-orkestr-namespace.yaml"
    "18a-orkestr-ci-rbac.yaml"
  ];
}
