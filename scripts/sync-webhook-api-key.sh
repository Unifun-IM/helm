#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-livekit}"
SECRET_NAME="${SECRET_NAME:-livekit-api-keys}"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl 未安装或不在 PATH 中" >&2
  exit 1
}

KEYS_YAML="$({
  kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" \
    -o jsonpath='{.data.keys\.yaml}'
} | base64 --decode)"

API_KEY="$(printf '%s\n' "${KEYS_YAML}" | awk -F ':' '
  /^[[:space:]]*#/ { next }
  NF >= 2 {
    key=$1
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    if (key != "") { print key; exit }
  }
')"

if [[ -z "${API_KEY}" ]]; then
  echo "无法从 ${NAMESPACE}/${SECRET_NAME} 的 keys.yaml 读取 API Key" >&2
  exit 1
fi

PATCH="$(printf '{\"stringData\":{\"webhook-api-key\":\"%s\"}}' "${API_KEY}")"

kubectl -n "${NAMESPACE}" patch secret "${SECRET_NAME}" \
  --type merge \
  -p "${PATCH}"

echo "已写入 ${NAMESPACE}/${SECRET_NAME}：webhook-api-key=${API_KEY}"
echo "该操作不会修改现有 keys.yaml 或 API Secret。"
