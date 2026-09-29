#!/usr/bin/env bash
# In-cluster image build for slopcannon.
#
# Harbor's registry is currently undeployable on this node (non-root UIDs get
# EPERM on socket(), and its image overlay denies root exec — needs a nixos
# fix, see infra/k8s/README.md). Until then images are delivered kaniko ->
# tar -> `ctr -n k8s.io images import` into the node's containerd store, and
# pods reference them with imagePullPolicy: Never. The tar still carries the
# Harbor destination name so a future `ctr images push` is one command.
#
# Usage: ./infra/k8s/kaniko-build.sh <web|render-worker> [tag]
set -euo pipefail

component="${1:?usage: kaniko-build.sh <web|render-worker> [tag]}"
tag="${2:-0.1.0}"

case "$component" in
	web) image="slopcannon-web"; dockerfile="apps/web/Dockerfile" ;;
	render-worker) image="slopcannon-render-worker"; dockerfile="workers/render/Dockerfile" ;;
	*) echo "unknown component: $component" >&2; exit 1 ;;
esac

job_name="${image}-build"
kubectl -n slopcannon delete job "${job_name}" --ignore-not-found --wait=false >/dev/null 2>&1 || true

token="$(sops -d "$HOME/Personal/nix/secrets/roles/backbone.yaml" |
	python3 -c "import sys,yaml;print(yaml.safe_load(sys.stdin)['argocd-forgejo-token'])")"

export FORGE_URL="http://Benjamin:${token}@forgejo-http.forgejo.svc:3000/Benjamin/slopcannon.git"
export IMAGE_REF="10.0.0.56:5000/library/${image}:${tag}"
export DOCKERFILE="${dockerfile}"

python3 - <<'EOF' | kubectl apply -f -
import os, yaml
job_name = os.environ["IMAGE_REF"].split("/")[-1].split(":")[0] + "-build"
y = {
	"apiVersion": "batch/v1",
	"kind": "Job",
	"metadata": {"name": job_name, "namespace": "slopcannon",
		"labels": {"app.kubernetes.io/name": job_name, "app.kubernetes.io/component": "image-build"}},
	"spec": {
		"backoffLimit": 0,
		"ttlSecondsAfterFinished": 7200,
		"template": {"metadata": {"labels": {"app.kubernetes.io/name": job_name}},
			"spec": {
				"restartPolicy": "Never",
				"tolerations": [
					{"key": "role", "value": "backbone", "effect": "NoSchedule"},
					{"key": "infra", "value": "true", "effect": "NoSchedule"}],
				"initContainers": [
					{"name": "git-clone",
					 "image": "alpine/git:latest@sha256:52be47b4d5ffd7e65439b4872d498897426c41afa38fde44d6c2f2f3249aaa97",
					 "command": ["sh", "-c", "mkdir -p /workspace/dist && git clone --depth 1 \"$FORGE_URL\" /workspace/src && git -C /workspace/src log --oneline -1"],
					 "env": [{"name": "FORGE_URL", "value": os.environ["FORGE_URL"]},
					         {"name": "HOME", "value": "/tmp"}],
					 "volumeMounts": [{"name": "workspace", "mountPath": "/workspace"}],
					 "securityContext": {"runAsUser": 0},
					 "resources": {"requests": {"cpu": "50m", "memory": "128Mi"},
					               "limits": {"cpu": "1", "memory": "1Gi"}}},
					{"name": "kaniko",
					 "image": "gcr.io/kaniko-project/executor:v1.23.2@sha256:8a4f9af8ef55ef8bfaf4cfd7b15dc956609e14a4402efefd5fb2e49a0c06e2c8",
					 "args": [f"--dockerfile=/workspace/src/{os.environ['DOCKERFILE']}",
					          "--context=/workspace/src",
					          f"--destination={os.environ['IMAGE_REF']}",
					          "--no-push",
					          f"--tar-path=/workspace/dist/{job_name}.tar",
					          "--snapshot-mode=redo", "--compression=zstd", "--force",
					          "--verbosity=info"],
					 "volumeMounts": [{"name": "workspace", "mountPath": "/workspace"}],
					 "resources": {"requests": {"cpu": "50m", "memory": "256Mi"},
					               "limits": {"cpu": "4", "memory": "4Gi"}}}],
				"containers": [
					{"name": "ctr-import",
					 "image": "alpine:3.20",
					 "command": ["sh", "-c",
						"/host-bin/ctr -a /host/run/containerd/containerd.sock -n k8s.io images import --all-platforms $(ls /workspace/dist/*.tar) && "
						"/host-bin/ctr -a /host/run/containerd/containerd.sock -n k8s.io images ls | grep slopcannon"],
					 "securityContext": {"privileged": True},
					 "volumeMounts": [{"name": "workspace", "mountPath": "/workspace"},
					                  {"name": "containerd-sock", "mountPath": "/host/run/containerd"},
					                  {"name": "host-bin", "mountPath": "/host-bin", "readOnly": True},
				                  {"name": "nix-store", "mountPath": "/nix/store", "readOnly": True}],
					 "resources": {"requests": {"cpu": "50m", "memory": "64Mi"},
					               "limits": {"cpu": "1", "memory": "512Mi"}}}],
				"volumes": [
					{"name": "workspace", "emptyDir": {"sizeLimit": "8Gi"}},
					{"name": "containerd-sock", "hostPath": {"path": "/run/containerd", "type": "Directory"}},
					{"name": "host-bin", "hostPath": {"path": "/run/current-system/sw/bin", "type": "Directory"}},
					{"name": "nix-store", "hostPath": {"path": "/nix/store", "type": "Directory"}}]}}}
}
print(yaml.safe_dump(y))
EOF

echo "waiting for job/${job_name} (logs: kubectl -n slopcannon logs job/${job_name} -c kaniko -f)"
if kubectl -n slopcannon wait --for=condition=complete "job/${job_name}" --timeout=60m; then
	echo "IMPORTED: ${IMAGE_REF} (use imagePullPolicy: Never)"
else
	echo "BUILD FAILED:" >&2
	kubectl -n slopcannon logs "job/${job_name}" -c kaniko --tail=40 >&2 || true
	kubectl -n slopcannon logs "job/${job_name}" -c ctr-import --tail=20 >&2 || true
	exit 1
fi
