#!/usr/bin/env bash
# 一次写入 LiveKit Secret：keys.yaml 与 webhook-api-key。
# 已存在的凭据默认不轮换，只补齐缺失的 webhook-api-key。
set -euo pipefail

SECRET_NAME="${SECRET_NAME:-livekit-api-keys}"
WEBHOOK_KEY_NAME="${WEBHOOK_KEY_NAME:-webhook-api-key}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-livekit}"

# 与 argocd/*.yaml 的 namespace、livekit.portOffset 保持一致。
# namespace offset
KNOWN_NAMESPACES=(
  "livekit 0"
  "livekit-dev 10"
  "livekit-p2 20"
  "im99 30"
)

usage() {
  cat <<'EOF'
用法：
  ./scripts/create-livekit-secret.sh
  NAMESPACE=livekit-dev ./scripts/create-livekit-secret.sh
  ./scripts/create-livekit-secret.sh --all

--all 会处理 livekit、livekit-dev、livekit-p2、im99。
已存在的 Secret 不会轮换 API Key / API Secret，只会补齐 webhook-api-key。
同时设置 LIVEKIT_API_KEY 和 LIVEKIT_API_SECRET 时，写入这一对凭据。
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 未安装或不在 PATH 中" >&2
    exit 1
  }
}

offset_for() {
  local ns="$1" item name offset
  for item in "${KNOWN_NAMESPACES[@]}"; do
    name="${item%% *}"
    offset="${item##* }"
    if [[ "${name}" == "${ns}" ]]; then
      printf '%s\n' "${offset}"
      return 0
    fi
  done
  return 1
}

print_ports() {
  local ns="$1" offset
  offset="$(offset_for "${ns}")" || return 0
  printf '节点防火墙：%s/TCP  %s/UDP（portOffset=%s）\n' \
    "$((7881 + offset))" "$((7882 + offset))" "${offset}"
}

api_key_from_keys() {
  awk -F ':' '
    /^[[:space:]]*#/ { next }
    NF >= 2 {
      key = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != "") { print key; exit }
    }
  '
}

secret_field() {
  local ns="$1" field="$2" encoded
  encoded="$(kubectl -n "${ns}" get secret "${SECRET_NAME}" \
    -o go-template="$(printf '{{index .data "%s"}}' "${field}")")"
  encoded="${encoded//$'\n'/}"
  encoded="${encoded//$'\r'/}"
  if [[ -z "${encoded}" || "${encoded}" == "<no value>" ]]; then
    return 0
  fi
  printf '%s' "${encoded}" | openssl base64 -d -A
}

secret_exists() {
  kubectl -n "$1" get secret "${SECRET_NAME}" >/dev/null 2>&1
}

deployment_exists() {
  kubectl -n "$1" get deploy "${DEPLOYMENT_NAME}" >/dev/null 2>&1
}

validate_token() {
  local name="$1" value="$2"
  if [[ ! "${value}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "${name} 只能包含字母、数字、下划线和连字符" >&2
    exit 1
  fi
}

write_secret() {
  local ns="$1" api_key="$2" api_secret="$3" tmp
  tmp="$(mktemp)"
  printf '%s: %s\n' "${api_key}" "${api_secret}" > "${tmp}"
  if ! kubectl -n "${ns}" create secret generic "${SECRET_NAME}" \
    --from-file=keys.yaml="${tmp}" \
    --from-literal="${WEBHOOK_KEY_NAME}=${api_key}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

patch_webhook_key() {
  local ns="$1" api_key="$2"
  kubectl -n "${ns}" patch secret "${SECRET_NAME}" --type merge \
    -p "$(printf '{"stringData":{"%s":"%s"}}' "${WEBHOOK_KEY_NAME}" "${api_key}")" \
    >/dev/null
}

ensure_namespace() {
  local ns="$1"
  echo "========== ${ns} =========="
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  local api_key="" api_secret="" existing_keys="" webhook_key="" changed=0

  if [[ -n "${LIVEKIT_API_KEY:-}" || -n "${LIVEKIT_API_SECRET:-}" ]]; then
    if [[ -z "${LIVEKIT_API_KEY:-}" || -z "${LIVEKIT_API_SECRET:-}" ]]; then
      echo "LIVEKIT_API_KEY 和 LIVEKIT_API_SECRET 需要同时提供" >&2
      exit 1
    fi
    validate_token "LIVEKIT_API_KEY" "${LIVEKIT_API_KEY}"
    validate_token "LIVEKIT_API_SECRET" "${LIVEKIT_API_SECRET}"
    api_key="${LIVEKIT_API_KEY}"
    api_secret="${LIVEKIT_API_SECRET}"
    write_secret "${ns}" "${api_key}" "${api_secret}"
    changed=1
    echo "已写入 ${ns}/${SECRET_NAME}"
  elif secret_exists "${ns}"; then
    existing_keys="$(secret_field "${ns}" "keys.yaml")"
    api_key="$(printf '%s\n' "${existing_keys}" | api_key_from_keys)"
    if [[ -z "${api_key}" ]]; then
      echo "无法从 ${ns}/${SECRET_NAME} 的 keys.yaml 读取 API Key" >&2
      exit 1
    fi
    webhook_key="$(secret_field "${ns}" "${WEBHOOK_KEY_NAME}")"
    if [[ "${webhook_key}" != "${api_key}" ]]; then
      patch_webhook_key "${ns}" "${api_key}"
      changed=1
      echo "已补齐 ${ns}/${SECRET_NAME} 的 ${WEBHOOK_KEY_NAME}"
    else
      echo "Secret 已存在且 webhook-api-key 已对齐：${ns}/${SECRET_NAME}"
    fi
    echo "未轮换现有 API Secret。"
  else
    require_cmd openssl
    api_key="$(openssl rand -hex 16)"
    api_secret="$(openssl rand -hex 32)"
    write_secret "${ns}" "${api_key}" "${api_secret}"
    changed=1
    echo "Secret 已创建：${ns}/${SECRET_NAME}"
    echo "LIVEKIT_API_SECRET=${api_secret}"
    echo "请立即保存 API Secret。之后重跑脚本不会再次显示。"
  fi

  echo "LIVEKIT_API_KEY=${api_key}"
  print_ports "${ns}"

  if [[ "${changed}" -eq 1 ]] && deployment_exists "${ns}"; then
    kubectl -n "${ns}" rollout restart "deploy/${DEPLOYMENT_NAME}" >/dev/null
    echo "已重启 deploy/${DEPLOYMENT_NAME}，使 webhook-api-key 生效。"
  fi
  echo
}

ALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd kubectl
require_cmd openssl

if [[ "${ALL}" -eq 1 && -n "${LIVEKIT_API_KEY:-}${LIVEKIT_API_SECRET:-}" ]]; then
  echo "--all 会为每个环境生成或保留各自的凭据，不能和 LIVEKIT_API_KEY / LIVEKIT_API_SECRET 一起使用。" >&2
  exit 1
fi

if [[ "${ALL}" -eq 1 ]]; then
  item=""
  for item in "${KNOWN_NAMESPACES[@]}"; do
    ensure_namespace "${item%% *}"
  done
else
  ensure_namespace "${NAMESPACE:-livekit}"
fi
