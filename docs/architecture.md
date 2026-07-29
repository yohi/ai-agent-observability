# 基本設計書（Architecture）

## 1. 概要

本設計書は、AIエージェント実行環境 監視・可視化システム（`ai-agent-observability`）の
基本設計を定めるものである。`docs/requirements.md`（要件定義書）で確定した要件を前提に、
実装設計時に確定すべき論点への決定、FR/NFRの実現手段とトレーサビリティ、および設計上の
リスク・未決事項を記録する。本文書は要件定義書の内容を変更するものではなく、要件定義書
第20章「確定事項」を前提としたうえで、要件を実現するための設計判断を追加するものである。

## 2. 確定事項

以下を最終決定事項とする（要件定義書第20章より）。

1. Cockpitはゲートウェイ用マシンでのみ使用する。
2. AIエージェント用マシンはSSHで管理する。
3. Cockpitマルチホスト機能は使用しない。
4. VictoriaMetricsおよびGrafanaはDocker Composeで動作させる。
5. Node ExporterおよびProcess Exporterはホスト上でsystemd管理する。
6. Tailscale、SSH、CockpitおよびCloudflare Tunnelはホスト上で動作させる。
7. Claude Code等のAIエージェント本体は原則としてホスト上で動作させる。
8. プロジェクト固有の開発・テスト環境は必要に応じてコンテナ化する。
9. 構成、設定、ダッシュボード、ドキュメントおよびテストは単一GitHubリポジトリで管理する。
10. メトリクス収集はTailscale経由とする。
11. Grafanaは原則としてTailscale経由で閲覧する。
12. Cloudflare Tunnel経由でGrafanaを公開する場合はCloudflare Accessを必須とする。
13. AIエージェント用マシンにCockpitを導入しない。
14. Pコア／Eコアの論理CPU番号を固定値として扱わない。
15. 高カーディナリティなPID、UUID、セッションID等を永続ラベルに使用しない。
16. APIキー、プロンプト全文、ソースコード本文等の機密情報を収集しない。
17. ゲートウェイ機自身および監視基盤も監視対象とする。
18. 監視基盤よりTailscale、Cloudflare TunnelおよびSSHの継続稼働を優先する。
19. コンテナイメージは明示的なバージョンへ固定する。
20. `latest`タグは使用しない。

## 3. 実装設計時に確定する事項

要件定義書第21章「実装設計時に確定する事項」14項目について、以下の決定を行った。

| 項番 | 論点 | 決定 |
|---|---|---|
| 1+2 | Process Exporterのグループ定義方式／cgroup併用 | 方式B-1: process-exporter単体＋cmdline正規表現の優先順序評価。特異的グループを先に、汎用comm(node/python)は`runtime:*`残余グループで受け、FR-007（node/python単独判定禁止）を満たす。cgroup/systemd scope併用はPhase 8送り（起動パス侵襲が北極星第2条件に抵触するため） |
| 3 | AIエージェント固有メトリクスの出力方式 | 案A: node_exporterのtextfile collector。hookがJSONL追記→systemd timer(30s)が.prom原子的差し替え。`ai_agent_*`プレフィクス固定で将来独自exporterへ無痛移行可能（NFR-020）。FR-026対応は`ai_agent_metrics_last_write_timestamp_seconds`の鮮度判定で代替 |
| 4 | Grafanaダッシュボードレイアウト | FR-021/022/023に1対1対応する3ダッシュボードのみ（overview/ai-agent/gateway）。datasourceは変数`$ds`（uid固定）で統一 |
| 5 | Alertingしきい値 | AL-001〜022を初期値としてprovisioning投入。「AI機の高負荷は正常」前提でforを長めに設定し誤報抑制 |
| 6 | VictoriaMetrics保持期間 | `-retentionPeriod=3`（3か月）＋`-storage.minFreeDiskSpaceBytes=20GiB`。見積り約8,000系列・3か月で2.1〜4.1GB |
| 7 | Dockerメモリ上限 | GW機8GB中、コンテナ割当2.75GB（VM: mem_limit 2g/allowedBytes 1.2GiB、Grafana: mem_limit 768m）。OOMScoreAdjust双方向設定（基幹サービス負値、コンテナ正値） |
| 8 | Grafana認証方式 | 初期: ローカル認証のみ（Anonymous無効、admin資格は`__FILE`経由）。将来公開時: Cloudflare Access + auth.jwt（auth.proxyは採らない） |
| 9 | Cloudflare Tunnel経由Grafana公開 | 初期構築では公開しない。config雛形はコメントアウトで用意 |
| 10 | 温度監視センサー | node_exporterのhwmon+thermal_zone collector。AI機（Core Ultra 7 270K）のcoretemp対応は実機確認要（OQ-005） |
| 11 | Ansible採用かシェルスクリプトか | Ansible採用（2層構成）: (1)bootstrap.sh（Tailscale導入・SSH鍵、shell）、(2)構成適用（Ansible）、(3)日常運用（Makefile）。要件側(§12.2/§12.4)が既にAnsibleを前提としている |
| 12 | プロジェクト識別方法 | 案B+A併用: `monitoring/projects.yaml`のregistry allowlist（SSOT）。cwdをpathsと照合、未登録は`unregistered`単一バケットへ丸める。動的値を絶対にラベル化しない設計 |
| 13 | 外部アラート通知先 | 【殿裁定により上書き済み】当初は「初期構築では設定しない」だったが、cmd_001でOQ-002として格上げ承認。本書8章のOQ-002を参照 |
| 14 | ログ基盤導入時期 | 初期構築では導入しない。定量トリガ3条件（MemAvailable40%以上・空き120GB以上・原因特定失敗3件累積）が揃った時点でPhase 8検討 |

### 重点4項目の詳細

**項番1+2（Process Exporterのグループ定義方式／cgroup併用）**
方式B-1（process-exporter単体＋cmdline正規表現の優先順序評価）を採用する。特異的な
プロセスグループ定義を優先順序の先頭で評価し、node/python等の汎用commは最後の
`runtime:*`残余グループで受けることで、FR-007（node/python単独判定禁止）を満たす。
cgroupやsystemd scopeとの併用構成はPhase 8へ送る。理由は、起動パス自体への侵襲的変更が
北極星第2条件（既存の起動フローを変えない）に抵触するためである。

**項番3（AIエージェント固有メトリクスの出力方式）**
案A（node_exporterのtextfile collector）を採用する。hookがイベントをJSONLへ追記し、
systemd timer（30秒間隔）が`.prom`ファイルを原子的に差し替える構成とする。メトリクス名を
`ai_agent_*`プレフィクスで固定することにより、将来独自exporterへ移行する際もダッシュボード・
アラート側を無変更で維持できる（NFR-020）。FR-026（死活監視）のうちagent-metricsに対応する
部分は、専用のscrape jobを持たないため`ai_agent_metrics_last_write_timestamp_seconds`の
鮮度判定によって代替する。

**項番11（Ansible採用かシェルスクリプトか）**
Ansibleを採用する。構成は2層とし、(1) `bootstrap.sh`によるTailscale導入・SSH鍵配布などの
初期シェル手順、(2) Ansibleによる恒常的な構成適用、(3) Makefileによる日常運用コマンド、
という役割分担とする。採用理由は、要件定義書§12.2および§12.4が既にAnsibleの使用を前提と
した記述になっているため、要件との整合性を優先したことによる。

**項番12（プロジェクト識別方法）**
案B（allowlist方式）と案A（cwd照合）を併用する。`monitoring/projects.yaml`を単一の
信頼できる情報源（SSOT）とし、実行時のcwdをこのファイル内のpathsと照合してプロジェクトIDを
解決する。allowlistに未登録のプロジェクトは`unregistered`という単一バケットへ丸め込む。
これにより、ラベルカーディナリティ制御（FR-009）の要件を満たしつつ、動的な値（未知の
ディレクトリ名等）が直接ラベルとして露出することを防止する。

## 4. FRトレーサビリティ表（FR-001〜FR-032）

| 要件ID | 実現手段 | 成果物パス |
| --- | --- | --- |
| FR-001 | node_exporterのcpu/loadavg/pressure/cpufreq/hwmon/thermal_zone collectorを有効化し、論理CPU別・PSI・周波数・温度・throttleを収集 | hosts/{ai-agent,gateway}/node-exporter/node_exporter.env, hosts/{ai-agent,gateway}/systemd/node_exporter.service |
| FR-002 | node_exporterのmeminfo/vmstat/pressure collector。OOMはnode_vmstat_oom_kill、swap in/outはnode_vmstat_pswpin/pswpout | hosts/{ai-agent,gateway}/node-exporter/node_exporter.env |
| FR-003 | node_exporterのfilesystem/diskstats/pressure collector。I/O待ちはnode_disk_io_time_weighted_seconds_total | hosts/{ai-agent,gateway}/node-exporter/node_exporter.env |
| FR-004 | node_exporterのnetdev/netstat/sockstat/tcpstat collector。tailscale0をnetdev device-includeに明示 | hosts/{ai-agent,gateway}/node-exporter/node_exporter.env |
| FR-005 | node_exporterのuname/time/loadavg/filefd/processes/systemd collector。systemdはunit-includeで監視対象unitに限定 | hosts/{ai-agent,gateway}/node-exporter/node_exporter.env |
| FR-006 | process-exporterのprocess_namesに8論理グループ＋2残余ランタイムグループを定義（第3章1+2項の決定） | hosts/ai-agent/process-exporter/process-exporter.yaml |
| FR-007 | 特異的cmdline正規表現を優先順序で先に評価し、node/python等の汎用commは最後のruntime:*残余グループが受ける（エージェントと分類しない） | hosts/ai-agent/process-exporter/process-exporter.yaml, docs/architecture.md |
| FR-008 | process-exporterを-children=true -threads=falseで起動し、子孫プロセスを先祖グループへ集約 | hosts/ai-agent/process-exporter/process_exporter.env, hosts/ai-agent/systemd/process_exporter.service |
| FR-009 | グループ名は静的リテラルのみ（Matchesはホワイトリスト化したcli名に限定）、-threads=false、projectはregistry allowlist、CIでラベル名を機械検証 | hosts/ai-agent/process-exporter/process-exporter.yaml, monitoring/projects.yaml, tests/configuration/test_label_cardinality.sh |
| FR-010 | ai_agent_running{agent_type,project} gaugeをhook＋集計スクリプトでtextfileへ出力 | hosts/ai-agent/scripts/agent_event_hook.sh, automation/scripts/agent_metrics_aggregate.sh |
| FR-011 | ai_agent_runs_total{result} / ai_agent_run_duration_seconds_{sum,count,max}を同機構で出力 | automation/scripts/agent_metrics_aggregate.sh |
| FR-012 | monitoring/projects.yamlのallowlistでpath→固定idを解決。未登録はproject="unregistered"へ丸め、動的値をラベル化しない | monitoring/projects.yaml, automation/scripts/agent_metrics_aggregate.sh |
| FR-013 | hookはevent/agent_type/project/result/duration_msのみ記録。出力時に禁止語フィルタを通し、CIで秘密情報混入を検査 | hosts/ai-agent/scripts/agent_event_hook.sh, tests/security/test_no_secrets_in_metrics.sh |
| FR-014 | prometheus.ymlに4 job（node/process/victoriametrics/grafana）＋agent-metrics（Phase6はnode同居、Phase8で独立）を定義。**殿裁定によりGrafana自身のメトリクスを6番目のscrape対象として追加**（本書8章OQ-001参照） | monitoring/victoriametrics/prometheus.yml, monitoring/victoriametrics/targets/*.yml |
| FR-015 | scrape targetをTailscale FQDN（*.ts.net）で指定し、UFWでTailscale IF以外からのexporter接続を拒否 | monitoring/victoriametrics/targets/ai-agent.yml, hosts/ai-agent/firewall/ufw.rules |
| FR-016 | prometheus.ymlのglobal.scrape_intervalを15s（.env変数で10〜30sに変更可能） | monitoring/victoriametrics/prometheus.yml, monitoring/.env.example |
| FR-017 | VictoriaMetrics起動引数-retentionPeriod=3（.envのVM_RETENTION_PERIODで可変） | monitoring/compose.yaml, monitoring/.env.example |
| FR-018 | VM自己メトリクス（vm_data_size_bytes, vm_free_disk_space_bytes）＋node filesystem＋predict_linearによる増加率監視 | monitoring/grafana/dashboards/gateway.json, monitoring/grafana/provisioning/alerting/rules-resource.yaml |
| FR-019 | 収集はVMからのpullのみ。AI機側はexporterとtextfileのみで監視基盤へ依存しない。push経路を作らない | docs/architecture.md, tests/acceptance/ac-019-independence.sh |
| FR-020 | Grafana datasource provisioning（type: prometheus, uid: victoriametrics, url: http://victoriametrics:8428） | monitoring/grafana/provisioning/datasources/victoriametrics.yaml |
| FR-021 | 概要ダッシュボード（uid: ai-obs-overview、5行構成）で11項目を1画面に配置 | monitoring/grafana/dashboards/overview.json |
| FR-022 | AI機ダッシュボード（uid: ai-obs-ai-agent、7行構成）で20項目を配置 | monitoring/grafana/dashboards/ai-agent.json |
| FR-023 | GW機ダッシュボード（uid: ai-obs-gateway、4行構成）で14項目を配置。**殿裁定により「VictoriaMetrics/Grafana自身のプロセスCPU/メモリ使用量」に表現修正**（本書8章OQ-001参照） | monitoring/grafana/dashboards/gateway.json |
| FR-024 | 全ダッシュボードのtimepicker.time_optionsに15m/1h/6h/24h/7d/30dを設定、既定now-1h | monitoring/grafana/dashboards/*.json |
| FR-025 | 採用前検証チェックリストを運用手順に明記し、CIでdatasource uid・job/instanceラベル・メトリクス名の整合を検査 | docs/operations.md, tests/configuration/test_dashboard_labels.sh |
| FR-026 | up==0ルール群＋systemd unit stateルール。agent-metricsのみai_agent_metrics_last_write_timestamp_secondsの鮮度で判定 | monitoring/grafana/provisioning/alerting/rules-availability.yaml |
| FR-027 | AL-004〜AL-022の初期しきい値（第3章5項の表）をprovisioningで投入 | monitoring/grafana/provisioning/alerting/rules-resource.yaml |
| FR-028 | **殿裁定によりDiscord外部通知を初期構築の必須機能とする**（Phase7格上げ、本書8章OQ-002参照） | monitoring/grafana/provisioning/alerting/{contact-points.example.yaml,notification-policies.yaml,alert-rules.yaml,README.md} |
| FR-029 | Ansible ai-agent playbookがSSH/Tailscaleを構成し、Cockpit不在をassertで保証 | automation/ansible/playbooks/ai-agent.yml, tests/acceptance/ac-007-cockpit-absence.sh |
| FR-030 | Ansible gateway playbookがCockpit（socket有効化）とSSHを構成 | automation/ansible/playbooks/gateway.yml, hosts/gateway/cockpit/cockpit.conf |
| FR-031 | Grafanaを127.0.0.1でのみpublishし、UFWでTailscale IFからの3000/tcpのみ許可。Tunnel ingressは既定無効 | monitoring/compose.yaml, hosts/gateway/firewall/ufw.rules, hosts/gateway/cloudflared/config.yml.example |
| FR-032 | UFWでCockpit 9090/tcpをTailscale IF限定。インターネット公開経路を作らない | hosts/gateway/firewall/ufw.rules, hosts/gateway/cockpit/cockpit.conf |

## 5. NFRトレーサビリティ表（NFR-001〜NFR-022）

| 要件ID | 実現手段 | 成果物パス |
| --- | --- | --- |
| NFR-001 | node_exporterの不要collectorを--no-collector.*で無効化、process-exporterを-threads=false -gather-smaps=false、両unitにCPUQuota=10%を設定、集計timerは30秒間隔 | hosts/ai-agent/node-exporter/node_exporter.env, hosts/ai-agent/process-exporter/process_exporter.env, hosts/ai-agent/systemd/*.service.d/limits.conf |
| NFR-002 | コンテナmem_limit合計を2.75GBに制限（8GB中）。MemAvailable<20%をAL-006で警告 | monitoring/compose.yaml, monitoring/grafana/provisioning/alerting/rules-resource.yaml |
| NFR-003 | 基幹サービスへsystemd OOMScoreAdjust負値（tailscaled/cloudflared/sshd -900、cockpit/docker -500）、コンテナへoom_score_adj正値（VM 500/Grafana 800）、mem_reservationで下限確保、restart: unless-stopped | hosts/gateway/systemd/*.service.d/oom.conf, monitoring/compose.yaml |
| NFR-004 | パネル数を1ダッシュボード20枚以下に抑制、maxDataPointsと最小stepを明示、$instance変数でクエリ対象を絞る | monitoring/grafana/dashboards/*.json, tests/acceptance/ac-004-dashboard-latency.sh |
| NFR-005 | Ansibleでsystemctl enable（sshd/tailscaled/node_exporter/process_exporter/docker/cloudflared/cockpit.socket）、composeにrestart: unless-stopped | automation/ansible/roles/*/tasks/main.yml, monitoring/compose.yaml |
| NFR-006 | systemd unitにRestart=always/RestartSec=5、composeにrestart: unless-stoppedとhealthcheck | hosts/*/systemd/*.service, monitoring/compose.yaml |
| NFR-007 | 起動順序に依存しない構成: exporterは全インターフェースでlistenし、UFWとTailscale ACLで接続元をTailscale経由のGW機のみに制限 | hosts/*/systemd/*.service, hosts/*/firewall/ufw.rules, docs/operations.md |
| NFR-008 | 全マシン間通信をTailscale（WireGuard）経由に限定。scrape targetもTailscale FQDN | automation/ansible/roles/tailscale/, monitoring/victoriametrics/targets/*.yml |
| NFR-009 | UFW default deny incoming。Node/Process Exporter・VM・SSH・Cockpit・Docker APIをpublishしない | hosts/*/firewall/ufw.rules, monitoring/compose.yaml, tests/security/test_no_public_ports.sh |
| NFR-010 | UFW（Tailscale IF限定allow）とTailscale ACLを併用 | hosts/*/firewall/ufw.rules, docs/operations.md, automation/tailscale-acl.example.json |
| NFR-011 | GF_AUTH_ANONYMOUS_ENABLED=false、GF_USERS_ALLOW_SIGN_UP=false、管理者資格は__FILE経由で.envから注入 | monitoring/compose.yaml, monitoring/.env.example, monitoring/grafana/grafana.ini |
| NFR-012 | node_exporterは専用system user。process-exporterは専用user＋AmbientCapabilities=CAP_SYS_PTRACEのみ付与。ProtectSystem=strict等のsystemd sandbox | hosts/ai-agent/systemd/process_exporter.service, hosts/*/systemd/node_exporter.service |
| NFR-013 | composeにprivileged/pid: host/docker.sock/ルートFSマウントを一切書かない。cap_drop: ALL、security_opt: no-new-privileges | monitoring/compose.yaml, tests/security/test_compose_privileges.sh |
| NFR-014 | .gitignoreで.envとdata/を除外。.env.exampleは変数名のみ。CIにgitleaks等の秘密情報スキャンを追加 | .gitignore, monitoring/.env.example, .github/workflows/secret-scan.yml |
| NFR-015 | §12.2の構成に沿って全構成要素を単一リポジトリで管理 | ai-agent-observability/ 全体 |
| NFR-016 | automation/scripts/bootstrap.sh→ansible-playbook site.ymlで新規Ubuntu環境から再構築 | automation/scripts/bootstrap.sh, automation/ansible/playbooks/site.yml, docs/disaster-recovery.md |
| NFR-017 | イメージタグを.env変数（VM_VERSION/GRAFANA_VERSION）で固定管理。latest/main/nightlyをCIで禁止検査 | monitoring/.env.example, monitoring/compose.yaml, tests/configuration/test_image_tags.sh |
| NFR-018 | VM・Grafanaデータをホスト側bind mountで永続化。provisioning/ダッシュボードはread-only mountでGit管理 | monitoring/compose.yaml, .gitignore |
| NFR-019 | scrape対象をfile_sd_configs化し、ホスト追加はtargets/への1ファイル追加のみで完結 | monitoring/victoriametrics/prometheus.yml, monitoring/victoriametrics/targets/, automation/ansible/inventory/ |
| NFR-020 | ai_agent_*メトリクス名とlabel集合を不変契約として文書化し、transport変更を無変更で差し替え可能にする | docs/architecture.md |
| NFR-021 | composeのネットワーク名を固定しcompose.logging.yamlをオーバーレイ可能に。収集はGrafana Alloy前提 | monitoring/compose.yaml, monitoring/grafana/provisioning/datasources/ |
| NFR-022 | file_sd_configsにGPU exporter用targetsファイルを追加するだけでscrape対象へ加えられる構成 | monitoring/victoriametrics/prometheus.yml, monitoring/victoriametrics/targets/ |

## 6. scrape対象の命名方針

instance = relabel_configsで固定名（ai-agent-01 / home-gateway-01）へ書き換える。
job名は役割ベース（node/process/agent-metrics/victoriametrics/grafana）とする。

| No | 論理対象 | job | instance | エンドポイント |
|---|---|---|---|---|
| 1 | AI機 node | node | ai-agent-01 | ai-agent-01.\<tailnet\>.ts.net:9100 |
| 2 | AI機 process | process | ai-agent-01 | ai-agent-01.\<tailnet\>.ts.net:9256 |
| 3 | AIエージェント固有メトリクス | agent-metrics | ai-agent-01 | Phase6はNo.1のtextfile collector経由でjob=node側に同居（物理scrape jobは存在しない。FR-026鮮度判定で代替） |
| 4 | GW機 node | node | home-gateway-01 | 127.0.0.1:9100 |
| 5 | VictoriaMetrics自身 | victoriametrics | home-gateway-01 | victoriametrics:8428 |
| 6 | Grafana自身（殿裁定により承認・OQ-001） | grafana | home-gateway-01 | grafana:3000/metrics |

## 7. 設計上のリスク

- AL-xxxしきい値は初期値。実測前は誤報/見逃しの可能性あり。Phase 7完了後30日を目安に見直しタスクを計画すること。
- VM保持期間のディスク見積り（0.5〜1.0 byte/サンプル）は仮定値。実測(vm_data_size_bytes)で置換すること。
- process-exporterへのCAP_SYS_PTRACE付与はNFR-012の最小権限とのトレードオフ。Phase 5でIOメトリクス取得可否を検証。
- textfile collector方式は.promの原子的差し替え（一時ファイル＋rename）必須。破損scrape防止の必須チェック項目。
- NFR-010のTailscale ACLはリポジトリで完結しない。月次確認にACL照合を追加推奨。
- Ansible採用によりcontrol node（外部PC）へのAnsible導入が前提。bootstrap.shに導入手順の案内を含めること。

## 8. 受入条件の追加

要件定義書第17章のAC-001〜016に続く追加分として、以下のAC-017〜AC-021を追加する。
いずれも殿の裁定（OQ-001・OQ-002承認）に伴い新設された受入条件である。

### OQ-001に伴う追加

**AC-017 Grafana自己監視**
> VictoriaMetricsがGrafanaの内部メトリクスを正常に収集し、Grafana自身のCPU使用時間、
> メモリ使用量および稼働状態をGrafanaダッシュボード上で確認できること。

### OQ-002に伴う追加

**AC-018 Discord通知**
> 試験用アラートを発火させた際に、Discordの指定チャンネルへ通知が送信されること。

**AC-019 復旧通知**
> 発火中の試験用アラートを正常状態へ戻した際に、復旧通知がDiscordへ送信されること。

**AC-020 秘密情報保護**
> Discord Webhook URLがGitHubリポジトリ、Grafanaダッシュボード、ログおよびCI出力へ
> 含まれていないこと。

**AC-021 通知独立性**
> Discord Webhookが無効または到達不能な場合でも、VictoriaMetricsによるメトリクス収集
> およびGrafanaのダッシュボード表示が継続すること。

## 9. 未決事項（Open Questions）

### OQ-001: Grafana自身のメトリクス追加（殿裁定・条件付き承認）

FR-014へ6番目のscrape対象として「Grafana自身が公開するPrometheus形式の内部メトリクス」を
追加する。ただし、cAdvisor等のコンテナ全体cgroup計測ではなく「Grafana自身のプロセス
CPU・メモリ」であることを明確にする条件付きで承認された。cAdvisorは導入しない。
FR-023についても「VictoriaMetricsコンテナ/Grafanaコンテナ」という表現を「VictoriaMetrics
自身/Grafana自身のプロセスCPU/メモリ使用量」へ表現修正する。scrape設定は
`job_name: grafana`、`targets: ["grafana:3000"]`、Compose内部ネットワークのサービス名で
解決し、追加公開ポートは不要である。

### OQ-002: Discord外部通知をPhase 8→Phase 7へ格上げ（殿裁定・承認）

外部アラート通知を任意機能から**Phase 7の初期構築必須機能**へ格上げすることが承認された。
FR-028修正版として、Grafana上でのアラート表示に加え、Discord Webhookを標準とした外部通知
先へのアラート送信を必須とする。Phase 7のタイトルも「アラート、外部通知および運用整備」へ
変更し、Discord Contact Point設定・通知ポリシー設定・Warning/Criticalルーティング・
通知抑制・復旧通知・通知テスト・Webhook秘密情報の注入手順作成を含める。Phase 8からは
「外部アラート通知」の項目を削除する。Webhook URLは秘密情報として扱い、リポジトリには
`contact-points.example.yaml`等の雛形のみを含め、実際のURLは`.env`等で注入する
（`.env.example`には値を入れない）。

既知の限界として、Grafana自身が停止した場合はGrafana AlertingからDiscordへ通知できない
自己監視上の限界が残るが、初期構成ではこれを許容する。

### OQ-003: 配置先（家老確定済み）

新規GitHubリポジトリは作成しない。cmd_001の制約により本リポジトリ（multi-agent-shogun）
内の新規ディレクトリ`ai-agent-observability/`配下に全成果物を配置する。

### OQ-004（決定不能・実機情報要）

prometheus.ymlのtargetsのTailnet名・実ホスト名が未提供のため確定不能。Phase 1のTailscale
接続確認時に埋める。

### OQ-005（決定不能・実機確認要）

AI機（Core Ultra 7 270K）のcoretempドライバ対応が未確認。確認手順は第3章「実装設計時に
確定する事項」の項番10を参照。

### OQ-006（要検証・Phase 5タスク）

process-exporterのcmdline正規表現が本リポジトリの実プロセス（claude/codex/opencode/
copilot/kimi等）に対して未検証。Phase 5で`ps -eo pid,comm,args`による実測突き合わせが
必須。
