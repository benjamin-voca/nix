#!/usr/bin/env python3
"""Snapshot an approved ZERO38 deploy directory into declarative K8s resources."""
import base64
import gzip
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tomllib

source = Path(sys.argv[1]).resolve()
if not (source / "index.html").is_file():
    raise SystemExit("Expected a built site directory with index.html")
spa = (source.parent / "package.json").is_file() and (source.parent / "netlify.toml").is_file()
buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode="w") as archive:
    for path in sorted(source.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if path.name in {"_headers", "_redirects", "netlify.toml"}:
            continue
        info = tarfile.TarInfo(path.relative_to(source).as_posix())
        content = path.read_bytes()
        info.size = len(content)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(content))
payload = gzip.compress(buffer.getvalue(), mtime=0)
digest = hashlib.sha256(payload).hexdigest()
namespace = "z38"
labels = {"app.kubernetes.io/name": "z38"}


def resource(api, kind, name, **fields):
    return {"apiVersion": api, "kind": kind,
            "metadata": {"name": name, "namespace": namespace, "labels": labels}, **fields}


resources = [{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": namespace}}]
chunks = []
# Stay below both the ConfigMap and API request size limits, including base64.
for index, start in enumerate(range(0, len(payload), 600_000)):
    name = f"z38-site-{index:03d}"
    key = f"part-{index:03d}"
    chunks.append({"configMap": {"name": name}})
    resources.append(resource("v1", "ConfigMap", name, binaryData={
        key: base64.b64encode(payload[start:start + 600_000]).decode()}))

# Preserve the security headers and short URLs from the Netlify deployment.
headers = []
for line in ((source / "_headers").read_text().splitlines() if (source / "_headers").exists() else []):
    if line.startswith("  ") and ":" in line and not line.strip().startswith(("X-Robots-Tag:", "Cache-Control:")):
        key, value = line.strip().split(":", 1)
        headers.append(f'add_header {key} "{value.strip()}" always;')
if spa:
    configuration = tomllib.loads((source.parent / "netlify.toml").read_text())
    global_headers = next(item["values"] for item in configuration["headers"] if item["for"] == "/*")
    headers = [f'add_header {key} "{value}" always;' for key, value in global_headers.items()]
nginx = """server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    server_tokens off;
    # Preserve the browser's public HTTPS origin behind Cloudflare/ingress.
    absolute_redirect off;
    charset utf-8;
    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    include /etc/nginx/security-headers.conf;
    location = /links { rewrite ^ /Links.dc.html last; }
    location = /bio { rewrite ^ /Links.dc.html last; }
    location = /HitLa-Z38tt.dc.html {
        include /etc/nginx/security-headers.conf;
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header Cache-Control "no-store" always;
        try_files $uri =404;
    }
    location / { try_files $uri $uri/ =404; }
}
"""
if spa:
    nginx = nginx.replace("    location = /links { rewrite ^ /Links.dc.html last; }\n", "")
    nginx = nginx.replace("    location = /bio { rewrite ^ /Links.dc.html last; }", "    location = /bio { return 301 /links; }")
    start = nginx.index("    location = /HitLa-Z38tt.dc.html {")
    end = nginx.index("    location / {", start)
    routes = []
    for item in configuration["redirects"]:
        if item.get("status") == 301 and item["from"] != "/bio":
            routes.append(f'    location = "{item["from"]}" {{ return 301 {item["to"]}$is_args$args; }}')
    for route in ("admin", "messages", "consent"):
        routes.append(f'''    location = /{route} {{
        include /etc/nginx/security-headers.conf;
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header Cache-Control "no-store" always;
        try_files /index.html =404;
    }}''')
    # Do not serve the SPA HTML as a successful API response. The server requires
    # separately configured database/email/auth credentials before activation.
    routes.append('''    location ~ ^/(api(?:/|$)|\\.netlify/functions/) {
        default_type application/json;
        add_header Cache-Control "no-store" always;
        return 503 '{"error":"Booking services are not configured yet. Please contact @zero38tattoos."}';
    }
    location /assets/ { try_files $uri =404; expires 1d; }
''')
    nginx = nginx[:start] + "\n".join(routes) + nginx[end:]
    nginx = nginx.replace("location / { try_files $uri $uri/ =404; }", "location / { try_files $uri $uri/ /index.html; }")
resources.append(resource("v1", "ConfigMap", "z38-nginx", data={
    "default.conf": nginx, "security-headers.conf": "\n".join(headers) + "\n"}))
mounts = [{"name": "site", "mountPath": "/usr/share/nginx/html", "readOnly": True},
          {"name": "nginx", "mountPath": "/etc/nginx/conf.d/default.conf", "subPath": "default.conf", "readOnly": True},
          {"name": "nginx", "mountPath": "/etc/nginx/security-headers.conf", "subPath": "security-headers.conf", "readOnly": True}]
resources.append(resource("apps/v1", "Deployment", "z38", spec={
    "replicas": 2, "selector": {"matchLabels": labels},
    "template": {"metadata": {"labels": labels, "annotations": {
        "z38.voltrum.co/site-sha256": digest,
        "z38.voltrum.co/config-sha256": hashlib.sha256((nginx + str(headers)).encode()).hexdigest()}},
        "spec": {"automountServiceAccountToken": False,
            "tolerations": [{"key": "role", "operator": "Equal", "value": "backbone", "effect": "NoSchedule"},
                            {"key": "infra", "operator": "Equal", "value": "true", "effect": "NoSchedule"}],
            "initContainers": [{"name": "unpack-site", "image": "nginx:1.28.0-alpine",
                "command": ["/bin/sh", "-ec", "cat /archive/part-* | tar xzf - -C /site"],
                "volumeMounts": [{"name": "archive", "mountPath": "/archive", "readOnly": True},
                                 {"name": "site", "mountPath": "/site"}],
                "resources": {"requests": {"cpu": "10m", "memory": "16Mi"}, "limits": {"cpu": "250m", "memory": "64Mi"}}}],
            "containers": [{"name": "nginx", "image": "nginx:1.28.0-alpine",
                "ports": [{"name": "http", "containerPort": 8080}], "volumeMounts": mounts,
                "securityContext": {"allowPrivilegeEscalation": False},
                "readinessProbe": {"httpGet": {"path": "/", "port": "http"}, "periodSeconds": 5},
                "livenessProbe": {"httpGet": {"path": "/", "port": "http"}, "periodSeconds": 20},
                "resources": {"requests": {"cpu": "10m", "memory": "32Mi"}, "limits": {"cpu": "250m", "memory": "128Mi"}}}],
            "volumes": [{"name": "archive", "projected": {"sources": chunks}},
                        {"name": "site", "emptyDir": {}}, {"name": "nginx", "configMap": {"name": "z38-nginx"}}]}}}))
resources.append(resource("v1", "Service", "z38", spec={"selector": labels,
    "ports": [{"name": "http", "port": 80, "targetPort": "http"}]}))
ingress = resource("networking.k8s.io/v1", "Ingress", "z38", spec={
    "ingressClassName": "nginx", "rules": [{"host": "z38.voltrum.co", "http": {"paths": [{
        "path": "/", "pathType": "Prefix", "backend": {"service": {"name": "z38", "port": {"number": 80}}}}]}}]})
ingress["metadata"]["annotations"] = {"nginx.ingress.kubernetes.io/ssl-redirect": "false",
                                      "nginx.ingress.kubernetes.io/backend-protocol": "HTTP"}
resources.append(ingress)
output = Path(__file__).with_name("resources.json")
output.write_text(json.dumps({"apiVersion": "v1", "kind": "List", "items": resources}, indent=2) + "\n")
print(f"Generated {output}: {len(payload)} compressed bytes, SHA256 {digest}")
