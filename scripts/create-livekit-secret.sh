#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-livekit}"
SECRET_NAME="${SECRET_NAME:-livekit-api-keys}"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl 未安装或不在 PATH 中" >&2
  exit 1
}

command -v openssl >/dev/null 2>&1 || {
  echo "openssl 未安装或不在 PATH 中" >&2
  exit 1
}

API_KEY="${LIVEKIT_API_KEY:-$(openssl rand -hex 16)}"
API_SECRET="${LIVEKIT_API_SECRET:-$(openssl rand -hex 32)}"

kubectl create namespace "${NAMESPACE}"   --dry-run=client -o yaml | kubectl apply -f -

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

printf '%s: %s\n' "${API_KEY}" "${API_SECRET}" > "${tmp_file}"

kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}"   --from-file=keys.yaml="${tmp_file}"   --dry-run=client -o yaml | kubectl apply -f -

echo
echo "Secret 已创建：${NAMESPACE}/${SECRET_NAME}"
echo "LIVEKIT_API_KEY=${API_KEY}"
echo "LIVEKIT_API_SECRET=${API_SECRET}"
echo
echo "请立即保存以上凭据。"
