# ai-agent-observability

AIエージェント実行環境（AIエージェント用マシン／宅内ゲートウェイ用マシン）のリソース使用状況とプロセス稼働状況を収集し、
宅内ゲートウェイ用マシン上のGrafanaダッシュボードから一元的に確認できる監視・可視化システムである。
Prometheus互換のメトリクス収集、VictoriaMetricsによる保存、Tailscale経由の安全な通信を用い、
監視自体がCloudflare Tunnel・Tailscale・SSH等の基幹サービスを阻害しないことを最優先方針とする。

詳細な要件は [docs/requirements.md](docs/requirements.md)、設計の決定内容は `docs/architecture.md`（後続タスクで作成）を参照。

## クイックスタート

> 本セクションは Phase 1（リポジトリおよび基盤準備）時点のプレースホルダである。
> 実際の導入手順は Phase 2 以降の実装が進んだ段階で肉付けする。

```bash
# 1. 環境変数ファイルを用意する
cp monitoring/.env.example monitoring/.env
# .env を編集し、必要な値（バージョン、パスワード等）を設定する

# 2. ブートストラップ（Tailscale導入・SSH鍵配置）を実行する（対象機ごと）
./automation/scripts/bootstrap.sh

# 3. Ansible で構成を適用する（後続タスクで実装）
# ansible-playbook -i automation/ansible/inventory/hosts.yml automation/ansible/playbooks/site.yml

# 4. 監視スタック（VictoriaMetrics / Grafana）を起動する（宅内ゲートウェイ用マシン）
make up
```

## ディレクトリ構成

主要ディレクトリの概要:

- `hosts/` — AIエージェント用マシン・宅内ゲートウェイ用マシンそれぞれのホスト上サービス設定
- `monitoring/` — VictoriaMetrics / Grafana の Docker Compose 構成とプロジェクトregistry
- `automation/` — Ansible構成とブートストラップ・集計スクリプト
- `tests/` — 設定・接続・セキュリティ・受入テスト
- `docs/` — 要件定義・設計・実装計画・運用・復旧手順
