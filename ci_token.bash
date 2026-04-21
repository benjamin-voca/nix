#!/usr/bin/env bash

 TOKEN=$(kubectl get secret gitea-ci-token -n orkestr -o jsonpath='{.data.token}' | base64 -d)
 CA=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
 SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

 cat <<EOF | base64
 apiVersion: v1
 kind: Config
 clusters:
 - cluster:
     certificate-authority-data: ${CA}
     server: ${SERVER}
   name: orkestr-cluster
 contexts:
 - context:
     cluster: orkestr-cluster
     namespace: orkestr
     user: gitea-ci
   name: gitea-ci
 current-context: gitea-ci
 users:
 - name: gitea-ci
   user:
     token: ${TOKEN}
 EOF
