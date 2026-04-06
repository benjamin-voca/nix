#!/usr/bin/env bash

set -euo pipefail

BASE_REF="${GITHUB_BASE_REF:-main}"

if git rev-parse --verify --quiet "origin/${BASE_REF}" >/dev/null; then
  RANGE="origin/${BASE_REF}...HEAD"
else
  RANGE="HEAD~1..HEAD"
fi

is_k8s_path() {
  case "$1" in
    modules/profiles/kubernetes/*)
      return 0
      ;;
    modules/outputs/bootstrap.nix|modules/outputs/bootstrap/*)
      return 0
      ;;
    modules/services/argocd-*.nix|modules/services/k8s-*.nix)
      return 0
      ;;
    charts/*|manifests/*|argocd-ingress.yaml)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

k8s_changed=0
while IFS= read -r path; do
  if [[ -n "$path" ]] && is_k8s_path "$path"; then
    k8s_changed=1
    break
  fi
done < <(git diff --name-only "$RANGE")

if [[ "$k8s_changed" -eq 0 ]]; then
  echo "No Kubernetes cluster changes in ${RANGE}; skipping git-cliff scope enforcement."
  exit 0
fi

allowed_regex='^(feat|fix|chore|refactor|docs|test|ci)\((k8s|argocd|harbor|helm|erpnext)\): .+'
checked_commits=0
violations=()

while IFS=$'\t' read -r sha subject; do
  [[ -z "$sha" ]] && continue

  commit_touches_k8s=0
  while IFS= read -r path; do
    if [[ -n "$path" ]] && is_k8s_path "$path"; then
      commit_touches_k8s=1
      break
    fi
  done < <(git diff-tree --no-commit-id --name-only -r "$sha")

  if [[ "$commit_touches_k8s" -eq 0 ]]; then
    continue
  fi

  checked_commits=$((checked_commits + 1))

  if [[ ! "$subject" =~ $allowed_regex ]]; then
    violations+=("${sha:0:12} ${subject}")
  fi
done < <(git log --no-merges --format='%H%x09%s' "$RANGE")

if [[ "$checked_commits" -eq 0 ]]; then
  echo "Kubernetes files changed, but no non-merge commits were found in ${RANGE}."
  echo "Skipping scope enforcement."
  exit 0
fi

if [[ "${#violations[@]}" -gt 0 ]]; then
  echo "Kubernetes cluster changes require conventional commit scopes: k8s, argocd, harbor, helm, or erpnext."
  echo "The following commits need scope fixes:"
  printf '  - %s\n' "${violations[@]}"
  exit 1
fi

echo "Kubernetes cluster commit scopes are valid for ${RANGE}."
