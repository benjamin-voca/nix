
set -gx gitea_db_password (SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-db-password: (.*)$" -r '$1')
                                  set -gx gitea_admin_password (SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixo
fish: Expected a variable name after this $.min-password: (.*)$" -r '$1')
set -gx gitea_db_password (SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-db-password: (.*)$" -r '$1') nix build .#helmCharts.x86_64-linux.all.gitea
                                                                                                                                                ^                 envsubst '${GITEA_DB_PASSWORD} ${GITEA_ADMIN_PASSWORD}' < ./result | kubectl applyroot@backbone-01 /e/nixos (main)# set -gx gitea_db_password (SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-db-password: (.*)\$" -r '$1')
                                  set -gx gitea_admin_password (SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-admin-password: (.*)\$" -r '$1')
                                  rm -f result
                                  nix build .#helmCharts.x86_64-linux.all.gitea
                                  GITEA_DB_PASSWORD="$gitea_db_password" GITEA_ADMIN_PASSWORD="$gitea_admin_password" \
                                        envsubst '${GITEA_DB_PASSWORD} ${GITEA_ADMIN_PASSWORD}' < ./result | kubectl apply -f -
                                  kubectl delete secret -n gitea gitea-init
                                  kubectl rollout restart -n gitea deployment/gitea
                                  kubectl delete pod -n gitea gitea-test-connection
