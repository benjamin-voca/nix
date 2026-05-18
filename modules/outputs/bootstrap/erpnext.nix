# ERPNext bootstrap module
# ERPNext namespace + helpdesk redirect ingress
{
  pkgs,
  lib,
}: let
  erpnextNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: erpnext
      labels:
        app.kubernetes.io/name: erpnext
  '';

  erpnextHelpdeskRedirect = ''
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: erpnext-helpdesk-redirect
      namespace: erpnext
      annotations:
        nginx.ingress.kubernetes.io/permanent-redirect: /desk/helpdesk
        nginx.ingress.kubernetes.io/permanent-redirect-code: "308"
    spec:
      ingressClassName: nginx
      rules:
      - host: helpdesk.quadtech.dev
        http:
          paths:
          - path: /helpdesk
            pathType: Exact
            backend:
              service:
                name: erpnext
                port:
                  number: 8080
          - path: /helpdesk/
            pathType: Prefix
            backend:
              service:
                name: erpnext
                port:
                  number: 8080
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "12aa-erpnext-namespace.yaml" = erpnextNamespace;
    "12a-erpnext-helpdesk-redirect-ingress.yaml" = erpnextHelpdeskRedirect;
  };

  order = [
    "12aa-erpnext-namespace.yaml"
    "12a-erpnext-helpdesk-redirect-ingress.yaml"
  ];
}
