# 実装計画書（導入フェーズ詳細化）

本書は [docs/requirements.md](requirements.md) 第18章「導入フェーズ」（Phase 1〜8）を、
実装可能な単位まで具体化したものである。Phase 7 は殿の裁定（OQ-002承認）による
全面改訂版を採用しており、`docs/requirements.md` の元のPhase 7記述より本書の記述を優先する。

情報源は以下2点のみであり、他の資料（`queue/reports/gunshi_report.yaml` 等）は使用していない。

- `docs/requirements.md`（第12.2節 推奨ディレクトリ構成、第17章 受入条件 AC-001〜016、第18章 導入フェーズ、第21章 実装設計時に確定する事項）
- 家老保存の恒久コンテキスト（軍師の基本設計決定＋殿の裁定、OQ-001〜003、FR/NFRトレーサビリティ表、file_inventory）

## 適用範囲

本計画書が対象とするのは、**殿が実機で辿れる手順書（設定ファイル・スクリプト・Ansible定義・
ドキュメント）をこのリポジトリ内に整備すること**までである。以下は範囲外とする。

- 実機（AIエージェント用マシン／宅内ゲートウェイ用マシン）へのSSH接続作業そのもの
- 実機上でのAnsible実行・Docker Compose起動等の導入作業そのもの

Phase 1〜6の各項目は `docs/requirements.md` 第18章の元の定義（成果物の粒度が未確定）を、
軍師の基本設計決定（file_inventory・FRトレーサビリティ表）で具体化したものである。
Phase 7 は家老保存コンテキストのPhase 7修正版（16項目）に基づく。Phase 8 は実装対象外。

---

## Phase 1：リポジトリおよび基盤準備

足軽1号（subtask_001a）によりディレクトリ構成・`README.md`・`Makefile`・`.gitignore`・
`.editorconfig`・`monitoring/.env.example`・`monitoring/projects.yaml` は作成済み。
本Phaseの残作業は、CI最小構成と、実機接続確認手順のドキュメント化である。

| 成果物ファイルパス | 内容 |
|---|---|
| `.github/workflows/ci.yml` | YAML構文・Docker Compose構文・Markdown lint等の最小CI（第12.4節） |
| `.github/workflows/secret-scan.yml` | 秘密情報混入検査（NFR-014） |
| `automation/scripts/bootstrap.sh` | 第21章11項決定の層構成のうち第1層。Tailscale導入・SSH鍵配置（shell） |
| `docs/operations.md`（新規、Phase1分のみ） | Tailscale接続確認手順・SSH接続確認手順（実機コマンド例のみ、実行はしない） |

- **依存関係**: 前工程なし（起点フェーズ）。足軽1号のリポジトリ雛形作成が前提。
- **検証方法**: YAML構文検証（`yamllint`相当）、Markdown lint、ShellCheck（`bootstrap.sh`）、
  CI自体がGitHub Actions上で実行できることの確認（構文エラーなくワークフローが起動すること）。
- **対応AC**: AC-015（モノレポ、既に満たされている）、AC-016（CI、最小構成が本Phaseで開始）。

---

## Phase 2：ホストメトリクス収集

| 成果物ファイルパス | 内容 |
|---|---|
| `hosts/ai-agent/node-exporter/node_exporter.env` | 収集対象collector有効化（FR-001〜005） |
| `hosts/ai-agent/systemd/node_exporter.service` | node_exporter systemd unit（専用system user、NFR-012） |
| `hosts/ai-agent/systemd/node_exporter.service.d/` 配下の limits.conf | CPUQuota等のリソース制限（NFR-001） |
| `hosts/ai-agent/firewall/ufw.rules` | Tailscale IF限定allow（NFR-009・010） |
| `hosts/gateway/node-exporter/node_exporter.env` | 同上（ゲートウェイ機） |
| `hosts/gateway/systemd/node_exporter.service` | 同上 |
| `hosts/gateway/firewall/ufw.rules` | 同上 |
| `automation/ansible/roles/tailscale/`, `roles/common/`, `roles/firewall/`, `roles/node_exporter/`, `roles/cockpit/` | 第21章11項の第2層（構成適用）。Cockpitはゲートウェイ機限定（FR-030、AC-007） |
| `automation/ansible/playbooks/site.yml`, `playbooks/ai-agent.yml`, `playbooks/gateway.yml` | 上記roleを呼び出すplaybook |
| `automation/ansible/inventory/` 配下の hosts定義 | OQ-004（Tailnet名・実ホスト名）は空欄プレースホルダとし、Phase1接続確認時に埋める前提のコメントを残す |

- **依存関係**: Phase 1完了後（`bootstrap.sh`によるTailscale導入・SSH鍵配置、CI基盤が前提）。
- **検証方法**: systemd unit構文チェック（`systemd-analyze verify`相当）、`ansible-lint`、
  UFWルール文法チェック、curlによるexporter応答確認手順の文書化（`http://<host>:9100/metrics`）、
  ShellCheck。
- **対応AC**: AC-001（基本メトリクス、開始）、AC-004（Tailscale収集）、AC-005（外部公開制限）、
  AC-006（SSH管理）、AC-007（Cockpit役割）、AC-009（再起動耐性、開始）、AC-010（監視負荷、開始）。

---

## Phase 3：監視バックエンド構築

| 成果物ファイルパス | 内容 |
|---|---|
| `monitoring/compose.yaml` | VictoriaMetrics・Grafanaのcompose定義（mem_limit、oom_score_adj、cap_drop: ALL等、NFR-002・003・013） |
| `monitoring/.env.example`（更新） | `VM_RETENTION_PERIOD`・`VM_VERSION`・`GRAFANA_VERSION`等バージョン変数追加（NFR-017） |
| `monitoring/victoriametrics/prometheus.yml` | job=node/process/victoriametrics/agent-metrics（Phase6まではnode同居）に加え、**殿裁定によりjob=grafanaを追加**（OQ-001、FR-014） |
| `monitoring/victoriametrics/targets/ai-agent.yml`, `targets/gateway.yml` | Tailscale FQDNでのscrape target定義（FR-015、OQ-004は実機確認後に埋める） |
| `automation/ansible/roles/docker/`, `roles/monitoring_stack/` | ゲートウェイ機へのDocker導入・compose起動のAnsible化 |

- **依存関係**: Phase 2完了後（scrape対象のNode Exporterが稼働していることが前提）。
- **検証方法**: `docker compose config`によるCompose構文検証、Prometheus互換設定検証
  （`promtool check config`相当）、起動確認・自動起動確認（`restart: unless-stopped`、
  healthcheck設定の存在確認）。
- **対応AC**: AC-004（継続）、AC-008（コンテナ構成）、AC-009（再起動耐性）、
  AC-011（ゲートウェイ安定性）、AC-017（Grafana自己監視、scrape開始のみ。可視化はPhase4で完了）。

---

## Phase 4：基本ダッシュボード

| 成果物ファイルパス | 内容 |
|---|---|
| `monitoring/grafana/provisioning/datasources/victoriametrics.yaml` | datasource provisioning（uid固定、FR-020） |
| `monitoring/grafana/provisioning/dashboards/`（provider定義） | ダッシュボードのファイルprovisioning設定 |
| `monitoring/grafana/dashboards/overview.json` | 概要ダッシュボード（uid: `ai-obs-overview`、5行11項目、FR-021） |
| `monitoring/grafana/dashboards/gateway.json` | ゲートウェイ監視画面（uid: `ai-obs-gateway`、4行14項目。VictoriaMetrics自己監視・Dockerコンテナ監視・**Grafana自身のプロセスCPU/メモリ**を含む、FR-023・OQ-001） |

- **依存関係**: Phase 3完了後（VictoriaMetrics・Grafanaが起動し、job=grafanaのscrapeが行われていること）。
- **検証方法**: GrafanaダッシュボードJSON構文検証、`tests/configuration/test_dashboard_labels.sh`
  によるdatasource uid・job/instanceラベル整合性検査（FR-025）。
- **対応AC**: AC-001（完了）、AC-003（ゲートウェイ監視）、AC-013（ディスク監視、VM保存容量を含めて完了）、
  AC-017（Grafana自己監視、完了）。

---

## Phase 5：AIエージェントプロセス監視

| 成果物ファイルパス | 内容 |
|---|---|
| `hosts/ai-agent/process-exporter/process-exporter.yaml` | 8論理グループ＋2残余ランタイムグループ、優先順序評価（第21章1+2項、FR-006・007） |
| `hosts/ai-agent/process-exporter/process_exporter.env` | `-children=true -threads=false -gather-smaps=false`（FR-008、NFR-001） |
| `hosts/ai-agent/systemd/process_exporter.service`, `process_exporter.service.d/limits.conf` | 専用user＋`AmbientCapabilities=CAP_SYS_PTRACE`のみ、CPUQuota（NFR-012） |
| `monitoring/projects.yaml`（既存ファイルの拡充） | registry allowlist方式でのプロジェクト識別（第21章12項、FR-012） |
| `monitoring/grafana/dashboards/ai-agent.json` | AI機ダッシュボード（uid: `ai-obs-ai-agent`、7行20項目、FR-022） |
| `automation/ansible/roles/process_exporter/` | 上記のAnsible化 |
| `tests/configuration/test_label_cardinality.sh` | ラベル名・カーディナリティのCI検証（FR-009） |

- **依存関係**: Phase 2（node_exporter稼働・Tailscale経由収集の基盤）およびPhase 4
  （Grafanaダッシュボード基盤）完了後。
- **検証方法**: process-exporter設定YAML構文検証、`ps -eo pid,comm,args`による実プロセス
  （claude/codex/opencode/copilot/kimi等）とのマッチング実測突き合わせ（**OQ-006、本Phase必須の検証事項**）、
  `test_label_cardinality.sh`によるカーディナリティ確認、systemd unit構文チェック。
- **対応AC**: AC-002（プロセス監視）、AC-010（監視負荷、継続確認）。

---

## Phase 6：AIエージェント固有メトリクス

| 成果物ファイルパス | 内容 |
|---|---|
| `hosts/ai-agent/scripts/agent_event_hook.sh` | event/agent_type/project/result/duration_msのみ記録するhook（FR-010・011・013） |
| `automation/scripts/agent_metrics_aggregate.sh` | JSONL追記→systemd timer(30s)による`.prom`原子的差し替え（一時ファイル＋rename、第21章3項） |
| `hosts/ai-agent/systemd/` 配下の `agent_metrics_aggregate.service`・`.timer` | 30秒間隔の集計timer |
| `hosts/ai-agent/node-exporter/node_exporter.env`（更新） | textfile collectorの有効化・ディレクトリ指定 |
| `automation/ansible/roles/agent_metrics/` | 上記のAnsible化 |
| `tests/security/test_no_secrets_in_metrics.sh` | 禁止語フィルタ・機密情報混入検査（FR-013） |

- **依存関係**: Phase 2（node_exporterのtextfile collector機構）完了後。Phase 5とはメトリクス経路が
  独立しているが、導入順序としてはPhase 5完了後に着手する。
- **検証方法**: `.prom`ファイルの原子的差し替え（一時ファイル＋rename）の動作検証、
  `test_no_secrets_in_metrics.sh`による機密情報混入検査、
  `ai_agent_metrics_last_write_timestamp_seconds`の鮮度判定ロジック検証（FR-026の代替判定）。
- **対応AC**: AC-014（機密情報、本Phaseの出力に対して開始）。

---

## Phase 7：アラート、外部通知および運用整備

**必読**: 本Phaseは家老保存コンテキスト（`context/ai-agent-observability.md`）のPhase 7修正版
（殿裁定OQ-002による全面改訂）に基づく。`docs/requirements.md`第18章の元のPhase7（7項目、
外部通知なし）は使用しない。

| 成果物ファイルパス | 対応する修正版16項目 |
|---|---|
| `monitoring/grafana/provisioning/alerting/rules-availability.yaml` | 死活監視、scrape失敗検知（up==0ルール群＋systemd unit stateルール、FR-026） |
| `monitoring/grafana/provisioning/alerting/rules-resource.yaml` | CPU／メモリ／ディスクアラート、OOM検知、PSIアラート（AL-004〜022初期値、FR-027） |
| （Phase3・4で導入済みのGrafana自己監視メトリクスに対するアラートルール。上記`rules-resource.yaml`に含める） | Grafana自己監視（取得失敗はWarning候補） |
| `monitoring/grafana/provisioning/alerting/contact-points.example.yaml` | Discord Contact Point設定（雛形のみ、Webhook URLは含めない） |
| `monitoring/grafana/provisioning/alerting/notification-policies.yaml` | Discord通知ポリシー設定、Warning／Criticalルーティング、通知抑制および再通知間隔の設定、復旧通知設定（`send_resolved`） |
| `monitoring/grafana/provisioning/alerting/alert-rules.yaml` | 上記アラートルールのGrafana Alerting形式での再構築定義 |
| `monitoring/grafana/provisioning/alerting/README.md` | Discord通知テスト手順、Webhook秘密情報の注入手順（`.env`経由、値はコミットしない） |
| `monitoring/.env.example`（更新） | `GF_ALERTING_DISCORD_WEBHOOK_URL=`（値は空、NFR-014） |
| `docs/operations.md`（更新） | 運用手順、Discord通知テスト実施手順 |
| `docs/disaster-recovery.md` | 復旧手順 |
| `tests/acceptance/ac-012-alerting.sh` | AC-012（アラート）受入試験 |
| `tests/acceptance/ac-017-grafana-self-monitoring.sh` | AC-017受入試験 |
| `tests/acceptance/ac-018-discord-notify.sh` | AC-018（Discord通知）受入試験 |
| `tests/acceptance/ac-019-discord-recovery.sh` | AC-019（復旧通知）受入試験 |
| `tests/security/test_no_secrets_in_metrics.sh`（Phase6作成分の拡張、Webhook URL検査を追加） | AC-020（秘密情報保護）検証 |
| `tests/acceptance/ac-021-notification-independence.sh` | AC-021（通知独立性）受入試験 |

- **依存関係**: Phase 4（Grafana Alerting provisioning基盤）およびPhase 6
  （`ai_agent_metrics_last_write_timestamp_seconds`による鮮度判定）完了後。実質的にPhase 1〜6
  完了後の最終フェーズ。
- **検証方法**: Grafana Alerting provisioningファイルのYAML構文検証、Discord Webhookへの
  試験通知の到達確認手順（実際の送信はリポジトリ外・実機作業のため手順書化のみ）、
  秘密情報混入検査（`.env.example`に値が入っていないことの確認、`gitleaks`相当のCIチェック）、
  Webhook無効時にもVictoriaMetrics収集・Grafana表示が継続することの手順確認（AC-021）。
- **対応AC**: AC-012（アラート）、AC-013（ディスク監視、アラート化により完了）、
  AC-017（Grafana自己監視、アラート化により完了）、AC-018（Discord通知）、
  AC-019（復旧通知）、AC-020（秘密情報保護）、AC-021（通知独立性）。

**厳禁事項の再確認**: 本Phaseの成果物にDiscord Webhook URLを平文で記載してはならない
（`contact-points.example.yaml`は雛形のみ）。実際の値は`.env`等で実機投入時に注入する。

---

## Phase 8：任意の高度化（実装対象外・将来検討事項のみ）

殿裁定（OQ-002）により「外部アラート通知」はPhase 7へ格上げ済みのため、Phase 8からは削除する。
本cmdでは以下を実装しない。将来検討事項として列挙するのみとする。

- Pコア／Eコア別表示
- systemd scopeまたはcgroupによるエージェント分離（第21章2項の決定によりPhase8送り）
- Loki導入（ログ基盤。第21章14項の決定により、定量トリガ3条件
  〈MemAvailable 40%以上・空き120GB以上・原因特定失敗3件累積〉が揃った時点で検討）
- OpenTelemetry導入
- GPU監視（NFR-022のfile_sd_configs化により、targetsファイル追加のみで将来対応可能な設計にしておく）
- 独自Exporterの分離（`ai_agent_*`メトリクス名の不変契約、NFR-020により無痛移行を想定）

---

## バッチ処理計画

CLAUDE.mdのバッチ処理プロトコル（30件/session、60Kトークン超のファイルがある場合は20件/session）
に準じ、Phase単位でバッチを分割する。各Phaseの成果物数は上限を大きく下回るため、
1バッチ＝1Phaseを基本とする。

| バッチ | 対象Phase | 想定ファイル数 |
|---|---|---|
| batch1 | Phase 1（CI最小構成・bootstrap.sh・接続確認手順） | 約4件 |
| batch2 | Phase 2（Node Exporter一式、両ホスト＋Ansible role×5＋playbook×3） | 約13件 |
| batch3 | Phase 3（監視バックエンド一式） | 約6件 |
| batch4 | Phase 4（Grafana基本ダッシュボード一式） | 約4件 |
| batch5 | Phase 5（Process Exporter一式＋AI機ダッシュボード） | 約8件 |
| batch6 | Phase 6（AIエージェント固有メトリクス一式） | 約6件 |
| batch7 | Phase 7（アラート・Discord通知・運用整備一式） | 約15件 |

## 品質ゲート

batch1（Phase 1）完了時点で、CI相当の静的検証（YAML構文・Markdown lint・ShellCheck・
CIワークフロー自体の起動確認）による品質チェックゲートを設ける。ここでNGが出た場合は
CLAUDE.mdのBatch Processing Protocol（③QC NG時のフロー）に従い、全体を停止して原因分析を行い、
batch2以降には進まない。batch1のQC OKを確認した後にのみbatch2以降を順次実行する。

---

## AC対応表（全体サマリ）

| AC | 内容 | 満たされ始めるPhase |
|---|---|---|
| AC-001 | 基本メトリクス | Phase2開始 / Phase4完了 |
| AC-002 | プロセス監視 | Phase5 |
| AC-003 | ゲートウェイ監視 | Phase4 |
| AC-004 | Tailscale収集 | Phase2開始 / Phase3継続 |
| AC-005 | 外部公開制限 | Phase2 |
| AC-006 | SSH管理 | Phase2 |
| AC-007 | Cockpit役割 | Phase2 |
| AC-008 | コンテナ構成 | Phase3 |
| AC-009 | 再起動耐性 | Phase2開始 / Phase3継続 |
| AC-010 | 監視負荷 | Phase2開始 / Phase5継続 |
| AC-011 | ゲートウェイ安定性 | Phase3 |
| AC-012 | アラート | Phase7 |
| AC-013 | ディスク監視 | Phase4開始 / Phase7完了 |
| AC-014 | 機密情報 | Phase6開始（継続監視） |
| AC-015 | モノレポ | Phase1 |
| AC-016 | CI | Phase1開始（継続拡充） |
| AC-017 | Grafana自己監視 | Phase3開始 / Phase4完了 / Phase7でアラート化 |
| AC-018 | Discord通知 | Phase7 |
| AC-019 | 復旧通知 | Phase7 |
| AC-020 | 秘密情報保護 | Phase7 |
| AC-021 | 通知独立性 | Phase7 |

Phase 1〜7すべてに対応するAC-xxxが存在することを確認済み。
