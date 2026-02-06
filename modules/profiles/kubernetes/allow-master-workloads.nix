{
  services.kubernetes.kubelet.extraOpts = "--node-labels=node-role.kubernetes.io/control-plane= --register-with-taints=";
}
