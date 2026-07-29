#!/usr/bin/env bash
#
# bootstrap.sh — 第21章11項決定の第1層（Ansible到達前提の構築）
#
# Ansibleが到達するための前提条件（SSH接続可能・Tailscale接続済み）を整える。
# 冪等: 既に導入済みの項目はスキップし、複数回実行しても安全なようにする。
#
# 対象: AIエージェント用マシン／宅内ゲートウェイ用マシン（対象ホスト上でsudo実行する想定）
#
# 前提となる環境変数:
#   TAILSCALE_AUTHKEY   Tailscale認証キー（未設定なら`tailscale up`の対話ログインを促す）
#
set -euo pipefail

log() {
  printf '[bootstrap] %s\n' "$1"
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
  if tailscale status >/dev/null 2>&1; then
    log "tailscale は既に接続済み（tailscale status 成功）。接続をスキップする。"
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
  sudo tailscale up --authkey="${TAILSCALE_AUTHKEY}"
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
  install_tailscale
  connect_tailscale
  setup_ssh_key
  check_ansible
  check_python3
  log "bootstrap.sh 完了。次工程: Ansibleによる構成適用（site.yml）へ進むこと。"
}

main "$@"
