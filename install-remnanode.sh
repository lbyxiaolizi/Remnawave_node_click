#!/usr/bin/env bash
set -euo pipefail

# Universal Remnawave Node installer (no YAML parsing here).
# Usage:
#   curl -fsSL https://example.com/install-remnanode.sh | sudo bash -s -- \
#     --project-dir /opt/remnanode \
#     --service remnanode \
#     --image remnawave/node:latest \
#     --network-mode host \
#     --restart always \
#     --node-port 2222 \
#     --secret-key '...'
#
# Optional:
#   --nofile-soft 1048576 --nofile-hard 1048576
#   --no-follow-logs

PROJECT_DIR="/opt/remnanode"
SERVICE="remnanode"
IMAGE="remnawave/node:latest"
NETWORK_MODE="host"
RESTART_POLICY="always"
NODE_PORT=""
SECRET_KEY=""
NOFILE_SOFT=""
NOFILE_HARD=""
FOLLOW_LOGS="yes"

usage() {
  cat <<'EOF'
Usage:
  install-remnanode.sh [options]

Required:
  --node-port <port>
  --secret-key <string>

Optional:
  --project-dir <dir>        (default: /opt/remnanode)
  --service <name>           (default: remnanode)
  --image <image:tag>        (default: remnawave/node:latest)
  --network-mode <mode>      (default: host)
  --restart <policy>         (default: always)
  --nofile-soft <n>
  --nofile-hard <n>
  --no-follow-logs           (do not tail logs)

Examples:
  curl -fsSL https://example.com/install-remnanode.sh | sudo bash -s -- \
    --node-port 2222 --secret-key 'xxx' --image remnawave/node:latest
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请用 root 运行：sudo bash install-remnanode.sh ..."
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) PROJECT_DIR="$2"; shift 2;;
      --service) SERVICE="$2"; shift 2;;
      --image) IMAGE="$2"; shift 2;;
      --network-mode) NETWORK_MODE="$2"; shift 2;;
      --restart) RESTART_POLICY="$2"; shift 2;;
      --node-port) NODE_PORT="$2"; shift 2;;
      --secret-key) SECRET_KEY="$2"; shift 2;;
      --nofile-soft) NOFILE_SOFT="$2"; shift 2;;
      --nofile-hard) NOFILE_HARD="$2"; shift 2;;
      --no-follow-logs) FOLLOW_LOGS="no"; shift 1;;
      -h|--help) usage; exit 0;;
      *) echo "未知参数：$1"; usage; exit 2;;
    esac
  done

  if [[ -z "${NODE_PORT}" || -z "${SECRET_KEY}" ]]; then
    echo "[ERR] 缺少必填参数：--node-port 和/或 --secret-key"
    usage
    exit 2
  fi
  if ! [[ "${NODE_PORT}" =~ ^[0-9]+$ ]] || (( NODE_PORT < 1 || NODE_PORT > 65535 )); then
    echo "[ERR] NODE_PORT 不合法：${NODE_PORT}"
    exit 2
  fi
}

install_docker() {
  if cmd_exists docker; then
    return
  fi
  echo "[..] 安装 Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker >/dev/null 2>&1 || true
}

ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    return
  fi
  echo "[..] 安装 docker-compose-plugin..."
  if cmd_exists apt-get; then
    apt-get update -y
    apt-get install -y docker-compose-plugin
  elif cmd_exists dnf; then
    dnf install -y docker-compose-plugin || dnf install -y docker-compose
  elif cmd_exists yum; then
    yum install -y docker-compose-plugin || yum install -y docker-compose
  fi
  docker compose version >/dev/null 2>&1 || { echo "[ERR] Docker Compose 不可用"; exit 1; }
}

write_compose() {
  mkdir -p "${PROJECT_DIR}"
  local compose_file="${PROJECT_DIR}/docker-compose.yml"

  # ulimits block optional
  local ulimits_block=""
  if [[ -n "${NOFILE_SOFT}" && -n "${NOFILE_HARD}" ]]; then
    ulimits_block=$'\n'"    ulimits:
      nofile:
        soft: ${NOFILE_SOFT}
        hard: ${NOFILE_HARD}"
  fi

  # escape backslashes and double quotes for YAML double-quoted string
  local sk="${SECRET_KEY//\\/\\\\}"
  sk="${sk//\"/\\\"}"

  cat > "${compose_file}" <<EOF
services:
  ${SERVICE}:
    container_name: ${SERVICE}
    hostname: ${SERVICE}
    image: ${IMAGE}
    network_mode: ${NETWORK_MODE}
    restart: ${RESTART_POLICY}${ulimits_block}
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY="${sk}"
EOF

  echo "[OK] 已写入 ${compose_file}"
}

start() {
  cd "${PROJECT_DIR}"
  docker compose up -d
  docker compose ps || true
  if [[ "${FOLLOW_LOGS}" == "yes" ]]; then
    docker compose logs -f -t --tail=200
  fi
}

main() {
  need_root
  parse_args "$@"
  install_docker
  ensure_compose
  write_compose
  echo
  echo "提示：建议仅允许“面板服务器 IP”访问 NODE_PORT=${NODE_PORT}（安全组/防火墙）。"
  echo
  start
}

main "$@"
