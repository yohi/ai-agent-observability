# 運用手順書（Phase 1分）

> **本ドキュメントの位置づけ**
> 本書は「殿が実機で辿れる手順書」である。ここに記載する接続確認コマンドは
> **実行例の提示のみ**であり、cmd_001（本タスクを含む一連の作業）の対象範囲には
> **実際に実機へ接続・実行する作業は含まれない**。実行は殿が実機環境で
> 判断・実施すること。
>
> 運用手順の全体（監視バックエンド運用、アラート対応、Discord通知運用等）は
> Phase 7で拡充する。本節はPhase 1の残作業として、実機接続確認手順のみを扱う。

## 1. 前提

- 対象ホスト: AIエージェント用マシン（`ai-agent-01`）、宅内ゲートウェイ用マシン（`home-gateway-01`）
- 全マシン間通信はTailscale（WireGuard）経由に限定する（NFR-008）。
- scrape対象やSSH接続先はTailscale FQDN（`*.ts.net`）で指定する（FR-015）。
- 実際のTailnet名・実ホスト名・IPアドレスは未確定（OQ-004）。本書では
  `<tailnet>` および `<host>` をプレースホルダとして使用する。実機確認後、
  `monitoring/victoriametrics/targets/*.yml` と合わせて埋めること。

## 2. Tailscale接続確認手順

対象ホスト上で、`automation/scripts/bootstrap.sh` によるTailscale導入・接続が
完了していることを前提に、以下のコマンドで状態を確認する。

```bash
# Tailscaleサービスの状態と、当該ホストが参加しているTailnet内の他ノードを一覧表示
tailscale status

# BackendStateがRunningであることを確認する（bootstrap.shの接続判定と同じ観点）
tailscale status --json | jq -r '.BackendState'

# ゲートウェイ機からAIエージェント機（またはその逆）への到達性確認
tailscale ping <host>.<tailnet>.ts.net
```

確認ポイント:

- `tailscale status` の出力に自ホストと対向ホストの両方が `active` として
  表示されること。
- `BackendState` が `Running` であること（`Stopped` 等の場合は
  `bootstrap.sh` の再実行、または `sudo tailscale up` を検討する）。
- `tailscale ping` が対向ホストからの応答を返すこと。

## 3. SSH接続確認手順

SSH接続はTailscale経由のみを前提とする（NFR-008・NFR-009）。公開鍵は
`bootstrap.sh` の `setup_ssh_key` 処理により対象ホストの `~/.ssh/authorized_keys`
へ追記される。

```bash
# Tailscale FQDN経由でのSSH接続確認（ホスト鍵検証を含む）
ssh <user>@<host>.<tailnet>.ts.net

# 接続後、対象ホスト側の主要サービス稼働状況を確認する例
ssh <user>@<host>.<tailnet>.ts.net 'systemctl is-active tailscaled sshd'
```

確認ポイント:

- Tailscale経由のFQDNでのみ接続でき、パブリックIP経由では接続できないこと
  （UFWによるTailscale IF限定allow、NFR-009・010）。
- 初回接続時のホスト鍵フィンガープリント確認を必ず行うこと（既知のホスト鍵で
  あることを事前に殿が把握しておく）。

## 4. bootstrap.sh の使い方

`automation/scripts/bootstrap.sh` は、Ansibleによる構成適用（第2層）が
到達するための前提条件（Tailscale接続・SSH鍵配置）を整える第1層のスクリプトである
（第21章11項の決定）。

### 実行方法

対象ホスト（AIエージェント用マシン／宅内ゲートウェイ用マシン）上で、
**一般ユーザーとして**実行する。

```bash
# auth keyを使わず対話ログインで接続する場合
./automation/scripts/bootstrap.sh

# auth keyを環境変数経由で渡す場合（コマンドライン引数には渡さない）
TAILSCALE_AUTHKEY='<tskey-...>' ./automation/scripts/bootstrap.sh

# SSH公開鍵の配置も同時に行う場合
TAILSCALE_AUTHKEY='<tskey-...>' SSH_PUBLIC_KEY='<公開鍵の内容>' \
  ./automation/scripts/bootstrap.sh
```

### 前提条件

- `jq` が導入済みであること（Tailscale接続状態の判定に使用）。未導入の場合、
  スクリプトは導入コマンド例を表示して終了する。
- `tailscale` コマンドが導入済みであること。未導入の場合、公式インストール
  スクリプトの案内を表示して終了する（本スクリプトは自動導入しない）。
- **root/sudoでスクリプト自体を実行しない**こと（`$HOME` が一般ユーザーの
  ホームである前提のため）。Tailscale接続等、内部で必要な箇所のみスクリプトが
  `sudo` を使用する。
- `TAILSCALE_AUTHKEY` を使う場合、auth keyをスクリプトへハードコードしない
  こと。環境変数経由でのみ渡す（コマンドライン引数経由だと `ps aux` 等で
  平文が露見するため、内部では一時ファイル経由に変換して使用する）。

### 冪等性

複数回実行しても安全なように設計されている。Tailscale導入済み・接続済み・
SSH公開鍵が既に `authorized_keys` に存在する場合は、それぞれの処理をスキップする。

### 実行範囲に関する注記

本書に記載の実行方法・コマンド例は手順の提示のみである。cmd_001の対象範囲に
**実機上での本スクリプトの実際の実行は含まれない**。実行判断・実施は殿が行うこと。

## 5. 次工程

`bootstrap.sh` による前提整備完了後は、Ansibleによる構成適用（`site.yml` ほか、
Phase 2以降で作成）へ進む。詳細は `docs/implementation-plan.md` のPhase 2以降を参照。
