#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_URL="backbone01:/etc/kubernetes/cluster-admin.kubeconfig"
CERTS_HOST_DIR="/var/lib/kubernetes/secrets"
BACKBONE_HOST="backbone01"
BACKBONE_LOCAL="backbone-01.local"
LOCAL_KUBECONFIG="$HOME/.kube/config.k8s"
LOCAL_CERTS="$HOME/.kube/certs"
WRAPPER_SCRIPT="$HOME/.local/bin/kubectl"

echo "=== Kubernetes Setup Script ==="
echo ""

# Check prerequisites
if ! command -v ssh &>/dev/null; then
    echo "❌ Error: ssh command not found"
    exit 1
fi

if ! command -v nc &>/dev/null; then
    echo "❌ Error: nc (netcat) not found — install it for SSH tunnel support"
    exit 1
fi

# Create directories
echo "📁 Creating ~/.kube directories..."
mkdir -p "$HOME/.kube/certs"
chmod 700 "$HOME/.kube"

# Add /etc/hosts entry if missing
if ! grep -q "$BACKBONE_LOCAL" /etc/hosts 2>/dev/null; then
    echo "🔧 Adding $BACKBONE_LOCAL to /etc/hosts..."
    echo "127.0.0.1 $BACKBONE_LOCAL" | sudo tee -a /etc/hosts > /dev/null
else
    echo "✓ /etc/hosts entry already exists"
fi

# Copy kubeconfig
# Uses cloudflared tunnel via ~/.ssh/config — no extra options needed
echo "📥 Copying kubeconfig from backbone01 (via cloudflared tunnel)..."
if ssh -o ConnectTimeout=15 "$BACKBONE_HOST" "sudo cat $KUBECONFIG_URL" 2>/dev/null | head -1 | grep -q 'apiVersion'; then
    ssh -o ConnectTimeout=15 "$BACKBONE_HOST" "sudo cat $KUBECONFIG_URL" > "$LOCAL_KUBECONFIG"
    echo "✓ kubeconfig saved to $LOCAL_KUBECONFIG"
else
    echo "❌ Error: Could not fetch kubeconfig from $KUBECONFIG_URL"
    echo "   Debug: ssh $BACKBONE_HOST 'sudo cat /etc/kubernetes/cluster-admin.kubeconfig'"
    exit 1
fi

# Copy certificates
echo "📥 Copying certificates from backbone01..."
CERTS=("ca.pem" "cluster-admin.pem" "cluster-admin-key.pem")
for cert in "${CERTS[@]}"; do
    content=$(ssh -o ConnectTimeout=15 "$BACKBONE_HOST" "sudo cat $CERTS_HOST_DIR/$cert" 2>/dev/null)
    if echo "$content" | head -1 | grep -qE 'BEGIN|END'; then
        echo "$content" > "$LOCAL_CERTS/$cert"
        echo "  ✓ $cert"
    else
        echo "  ⚠ Warning: $cert not found on backbone01"
    fi
done

# Create kubectl wrapper script
echo "🔧 Creating kubectl wrapper script..."
mkdir -p "$(dirname "$WRAPPER_SCRIPT")"

cat > "$WRAPPER_SCRIPT" << 'WRAPPER'
#!/bin/bash
# kubectl wrapper for backbone-01.local cluster
# Handles --context=selfhosted by starting SSH tunnel and fetching certs remotely

wanted_context=""
i=0
for arg in "$@"; do
    if [[ "$arg" == "--context="* ]]; then
        wanted_context="${arg#--context=}"
    elif [[ "$i" -eq 0 ]] && [[ "$arg" == "use-context" || "$arg" == "set-context" ]]; then
        next=true
    elif [[ "$next" == "true" ]] && [[ "$arg" != -* ]]; then
        wanted_context="$arg"
        next=false
    fi
    i=$((i + 1))
done

if [[ "$wanted_context" != "selfhosted" ]]; then
    exec /usr/local/bin/kubectl "$@"
fi

context=$(/usr/local/bin/kubectl config current-context 2>/dev/null)

if [[ "$context" == "selfhosted" ]]; then
    # Check if local port 6443 is listening (from SSH tunnel)
    if ! nc -z localhost 6443 2>/dev/null; then
        echo "Starting SSH tunnel to backbone01..." >&2
        ssh -L 6443:localhost:6443 -f -N backbone01 2>/dev/null
        sleep 2
    fi
    
    kubeconfig=$(mktemp)
    trap "rm -f $kubeconfig" EXIT
    
    ssh -o ConnectTimeout=5 backbone01 "sudo cat /etc/kubernetes/cluster-admin.kubeconfig" 2>/dev/null | \
        sed 's|backbone-01.local|127.0.0.1|g' | \
        sed 's|/var/lib/kubernetes/secrets/||g' > "$kubeconfig"
    
    ssh_cert=$(mktemp)
    ssh_key=$(mktemp)
    ssh_ca=$(mktemp)
    trap "rm -f $kubeconfig $ssh_cert $ssh_key $ssh_ca" EXIT
    
    ssh -o ConnectTimeout=5 backbone01 "sudo cat /var/lib/kubernetes/secrets/cluster-admin.pem" > "$ssh_cert"
    ssh -o ConnectTimeout=5 backbone01 "sudo cat /var/lib/kubernetes/secrets/cluster-admin-key.pem" > "$ssh_key"
    ssh -o ConnectTimeout=5 backbone01 "sudo cat /var/lib/kubernetes/secrets/ca.pem" > "$ssh_ca"
    
    sed -i.bak "s|cluster-admin.pem|$ssh_cert|g; s|cluster-admin-key.pem|$ssh_key|g; s|ca.pem|$ssh_ca|g" "$kubeconfig"
    
    export KUBECONFIG=$kubeconfig
fi

exec /usr/local/bin/kubectl "$@"
WRAPPER

chmod +x "$WRAPPER_SCRIPT"
echo "✓ Wrapper script installed at $WRAPPER_SCRIPT"

# Add to shell profile if not already present
SHELL_RC="${HOME}/.zshrc"
[[ -n "${BASH_VERSION:-}" ]] && SHELL_RC="${HOME}/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && SHELL_RC="${HOME}/.zshrc"

if [[ -f "$SHELL_RC" ]] && ! grep -q '^\s*export PATH=.*\.local/bin.*kubectl' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo "✓ Added .local/bin to PATH in $SHELL_RC"
else
    echo "✓ PATH already configured in $SHELL_RC"
fi

# Set default context
echo ""
echo "🔄 Setting default context to 'backbone'..."
"$WRAPPER_SCRIPT" config use-context backbone 2>/dev/null || \
    /usr/local/bin/kubectl config use-context backbone

# Verify
echo ""
echo "=== Verification ==="
if "$WRAPPER_SCRIPT" get nodes --context=backbone &>/dev/null; then
    echo "✅ Cluster connection successful!"
    "$WRAPPER_SCRIPT" get nodes
else
    echo "⚠️  Cluster not reachable from this machine (may need direct access)"
    echo "   The setup is complete. For machines without direct cluster access,"
    echo "   use: kubectl --context=selfhosted <command>"
fi

echo ""
echo "=== Setup Complete ==="
echo "Run: source ~/${SHELL_RC##*/}  # or restart your terminal"
echo "Then: kubectl get nodes"