# Kubelet container image garbage collection.
#
# Without these settings the kubelet only GCs images when the disk passes
# the high watermark (default 85%), which never triggers on hosts with a
# large root disk. Stale images from old deployments accumulate forever:
# an audit on backbone-01 (2026-08) found 599 image IDs on disk of which
# only 66 were referenced by any container (533 unused, ~162G containerd).
#
# - imageMaximumGCAge (k8s >= 1.30): unused images older than this are
#   removed even when the disk is below the GC thresholds.
# - Lower high/low watermarks so GC also reacts earlier once the disk
#   starts filling up.
{
  config,
  pkgs,
  ...
}: {
  services.kubernetes.kubelet.extraConfig = {
    imageGCHighThresholdPercent = 70;
    imageGCLowThresholdPercent = 50;
    imageMaximumGCAge = "24h";
  };
}
