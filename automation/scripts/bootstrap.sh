#!/usr/bin/env bash
#
# bootstrap.sh — 第21章11項決定の第1層（Ansible到達前提の構築）
#
# Ansibleが到達するための前提条件（SSH接続可能・Tailscale接続済み）を整える。
# 冪等: 既に導入済みの項目はスキップし、複数回実行しても安全なようにする。
#
# 対象: AIエージェント用マシン／宅内ゲートウェイ用マシン
#       （対象ホスト上で一般ユーザーとして実行し、必要な箇所（tailscale up等）のみ
#        内部でsudoを使う想定。$HOMEが一般ユーザーのホームである前提のため、
#        本スクリプト自体をsudoやrootで実行してはならない）
#
# 前提となる環境変数:
#   TAILSCALE_AUTHKEY   Tailscale認証キー（未設定なら`tailscale up`の対話ログインを促す）
#
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Do not run as root" >&2
  exit 1
fi

log() {
  printf '[bootstrap] %s\n' "$1"
}

# connect_tailscale内で一時ファイルパスを保持する（EXITトラップから参照するため
# グローバルスコープに置く。local変数だと関数を抜けた時点で可視域が失われ、
# トラップ実行時に`set -u`で未割り当て変数エラーとなる）。
AUTHKEY_FILE=""

cleanup() {
  [ -n "${AUTHKEY_FILE}" ] && rm -f "${AUTHKEY_FILE}"
  return 0
}
trap cleanup EXIT

# --- 0. jqの存在確認（Tailscale接続状態の判定に必要） -------------------------

check_jq() {
  if command -v jq >/dev/null 2>&1; then
    return
  fi

  log "jq が見つからない。Tailscale接続状態の判定に必要である。"
  log "  sudo apt-get update && sudo apt-get install -y jq"
  log "導入後、本スクリプトを再実行すること。"
  exit 1
}

# --- 1. Tailscaleのインストール確認・導入 -----------------------------------

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    log "tailscale は既に導入済み。インストールをスキップする。"
    return
  fi

  log "tailscale コマンドが見つからない。公式インストールスクリプトの導入が必要。"
  log "以下のコマンドで導入せよ（本スクリプトは自動実行しない）:"
  log "  curl -fsSL https://tailscale.com/install.sh | sh"
  log "導入後、本スクリプトを再実行すること。"
  exit 1
}

connect_tailscale() {
  # `tailscale status`は停止中(BackendState=Stopped等)でも終了コード0を返す
  # ことがあるため、終了コードのみでは接続済みと誤判定する（QC-019）。
  # BackendStateがRunningであることを明示的に確認する。
  if [ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')" = "Running" ]; then
    log "tailscale は既に接続済み（BackendState=Running）。接続をスキップする。"
    return
  fi

  if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    log "TAILSCALE_AUTHKEY 環境変数が未設定。対話ログインで接続する:"
    log "  sudo tailscale up"
    log "auth keyを使う場合は環境変数 TAILSCALE_AUTHKEY を設定してから再実行すること。"
    log "（auth keyを本スクリプトへハードコードすることは禁止）"
    exit 1
  fi

  log "TAILSCALE_AUTHKEY を用いて tailscale up を実行する。"
  # auth keyをコマンドライン引数として渡すと /proc/<pid>/cmdline 経由で
  # 同一マシン上の他プロセス（ps aux等）から平文で読み取られる（QC-017）。
  # file: 形式で一時ファイル経由に渡し、使用後は直ちに削除する。
  AUTHKEY_FILE="$(mktemp -t tailscale-authkey.XXXXXX)"
  chmod 600 "${AUTHKEY_FILE}"
  printf '%s' "${TAILSCALE_AUTHKEY}" > "${AUTHKEY_FILE}"
  sudo tailscale up --auth-key="file:${AUTHKEY_FILE}"
  rm -f "${AUTHKEY_FILE}"
  AUTHKEY_FILE=""
}

# --- 2. SSH鍵配置の確認 ------------------------------------------------------

setup_ssh_key() {
  local ssh_dir="${HOME}/.ssh"
  local authorized_keys="${ssh_dir}/authorized_keys"

  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
    log "SSH_PUBLIC_KEY 環境変数が未設定。SSH公開鍵の配置をスキップする。"
    log "配置する場合は環境変数 SSH_PUBLIC_KEY に公開鍵の内容を設定して再実行すること。"
    return
  fi

  touch "${authorized_keys}"
  chmod 600 "${authorized_keys}"

  if grep -qF "${SSH_PUBLIC_KEY}" "${authorized_keys}" 2>/dev/null; then
    log "指定された公開鍵は既に authorized_keys に存在する。追記をスキップする（既存鍵は上書きしない）。"
    return
  fi

  log "公開鍵を authorized_keys へ追記する（既存の鍵は保持する）。"
  printf '%s\n' "${SSH_PUBLIC_KEY}" >> "${authorized_keys}"
}

# --- 3. Ansible導入確認（control node側） -----------------------------------

check_ansible() {
  if command -v ansible >/dev/null 2>&1; then
    log "ansible は既に導入済み（control node側）。"
    return
  fi

  log "ansible コマンドが見つからない（control node側での導入が必要）。"
  log "導入手順の例:"
  log "  sudo apt-get update && sudo apt-get install -y ansible"
  log "または: python3 -m pip install --user ansible"
}

# --- 4. python3の存在確認（Ansibleの前提） -----------------------------------

check_python3() {
  if command -v python3 >/dev/null 2>&1; then
    log "python3 は導入済み（$(python3 --version 2>&1)）。"
    return
  fi

  log "python3 が見つからない。Ansibleの実行にはpython3が必要。導入手順の例:"
  log "  sudo apt-get update && sudo apt-get install -y python3"
}

main() {
  check_jq
  install_tailscale
  connect_tailscale
  setup_ssh_key
  check_ansible
  check_python3
  log "bootstrap.sh 完了。次工程: Ansibleによる構成適用（site.yml）へ進むこと。"
}

main "$@"
