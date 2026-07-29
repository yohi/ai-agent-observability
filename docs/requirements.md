> 本ドキュメントは multi-agent-shogun/REQUIREMENTS.md を移設したものである。

# AIエージェント実行環境 監視・可視化システム要件定義書

**最終決定版**

---

## 1. 文書情報

| 項目   | 内容                                               |
| ---- | ------------------------------------------------ |
| 文書名  | AIエージェント実行環境 監視・可視化システム要件定義書                     |
| 版    | 1.0 最終決定版                                        |
| 対象   | AIエージェント用マシン／宅内ゲートウェイ用マシン                        |
| 管理方式 | 単一GitHubリポジトリによるモノレポ管理                           |
| 監視方式 | Prometheus互換メトリクス収集・VictoriaMetrics保存・Grafana可視化 |
| 管理経路 | Tailscaleを利用したSSHおよびWebアクセス                      |

---

# 2. 目的

本システムは、Claude Code等のAIエージェントを複数並列実行する「AIエージェント用マシン」のリソース使用状況および関連プロセスの稼働状況を収集し、「宅内ゲートウェイ用マシン」上のWebダッシュボードから一元的に確認できる監視・可視化環境を構築することを目的とする。

本システムにより、以下を実現する。

* AIエージェント用マシンのCPU、メモリ、ストレージ、ネットワーク状態の把握
* Claude Code等のAIエージェント関連プロセスによるリソース消費量の把握
* 複数AIエージェントの並列実行に伴うリソース逼迫の早期発見
* swap、OOM、I/O待ち、CPU負荷、温度上昇等の異常検知
* 宅内ゲートウェイ用マシンを含む監視基盤全体の状態確認
* 外部PCからの安全な監視情報閲覧
* 監視基盤がCloudflare Tunnel、Tailscale等の基幹サービスを阻害しない運用
* 構成情報、設定、ダッシュボード、テストおよびドキュメントの一元管理

---

# 3. 背景

AIエージェント用マシンでは、Claude Code等のAIエージェントを複数並列実行する。

AIエージェントは、LLM APIへの通信だけでなく、以下の処理を動的に実行する。

* ソースコード検索
* ソースコード解析
* Git操作
* ビルド
* テスト
* Node.js、Python、Rust等のランタイム実行
* ripgrep等の短寿命プロセスの生成
* MCPサーバーの起動
* 開発用コンテナの起動
* 複数ワークスペースに対する並列処理

これらの処理は、CPU、メモリ、ストレージI/Oおよびプロセス数に大きな変動を発生させる。

単純なCPU使用率やメモリ使用率だけでは、以下を判断できない。

* どのAIエージェント関連処理がリソースを消費しているか
* 並列実行数が適切か
* ビルド、テスト、コード検索のどこがボトルネックか
* メモリ不足やI/O待ちが性能低下の原因となっているか
* プロセスの増加や異常終了が発生しているか

一方、監視情報を保存・表示する宅内ゲートウェイ用マシンは、8GBメモリ、256GBストレージという制約があり、Cloudflare Tunnel、Tailscale、Cockpit等を常時稼働させる。

そのため、監視システムには以下が必要である。

* 低い監視オーバーヘッド
* 低いメモリ消費
* 低いストレージ消費
* 高カーディナリティを避けたメトリクス設計
* 管理系サービスを優先するリソース制御
* マシン間通信の暗号化
* 障害時にAIエージェントの実行を妨げない構成
* 再構築可能な構成管理

---

# 4. 対象マシン

## 4.1 AIエージェント用マシン

### 4.1.1 ハードウェア

| 項目    | 内容                                           |
| ----- | -------------------------------------------- |
| CPU   | Intel Core Ultra 7 270K Plus                 |
| CPU構成 | Pコア8、Eコア16、合計24コア24スレッド                      |
| メモリ   | DDR5-6400 32GB × 2、合計64GB                    |
| ストレージ | Western Digital WD_BLACK SN7100 1TB NVMe SSD |
| OS    | Ubuntu Server 26.04                          |

### 4.1.2 主用途

* Claude Code等のAIエージェントの複数並列実行
* ソースコード検索および解析
* Git操作
* ビルド
* テスト
* MCPサーバーの実行
* 開発用コンテナの実行

### 4.1.3 管理方針

AIエージェント用マシンにはCockpitを導入しない。

システム管理は、外部PCからTailscale経由のSSHを用いて行う。

---

## 4.2 宅内ゲートウェイ用マシン

### 4.2.1 ハードウェア

| 項目    | 内容                  |
| ----- | ------------------- |
| CPU   | Intel Core i5 第6世代  |
| メモリ   | 8GB                 |
| ストレージ | M.2 SSD 256GB       |
| OS    | Ubuntu Server 26.04 |

### 4.2.2 主用途

* Cloudflare Tunnelの常駐
* Tailscaleの常駐
* Cockpitによるゲートウェイ機自身の管理
* メトリクスの収集および保存
* GrafanaによるWebダッシュボード表示
* 監視基盤の稼働

### 4.2.3 管理方針

Cockpitは宅内ゲートウェイ用マシン自身の管理にのみ使用する。

以下は行わない。

* CockpitによるAIエージェント用マシンの管理
* Cockpitマルチホスト機能の利用
* AIエージェント用マシンへの`cockpit-bridge`導入
* Cockpit経由のAIエージェント用マシンへのSSH接続

---

# 5. システム基本方針

## 5.1 責務分離

本システムは、以下の責務を分離する。

| レイヤー     | 責務                                  |
| -------- | ----------------------------------- |
| 実行レイヤー   | AIエージェント、ビルド、テスト、MCPサーバー等の実行        |
| 収集レイヤー   | ホストおよびプロセスのメトリクス公開                  |
| 保存レイヤー   | 時系列メトリクスの収集、保存、検索                   |
| 可視化レイヤー  | ダッシュボード表示およびアラート                    |
| 管理レイヤー   | SSHまたはCockpitによるOS管理                |
| 通信レイヤー   | Tailscaleおよび必要に応じたCloudflare Tunnel |
| 構成管理レイヤー | GitHubモノレポによる設定、コード、文書、テストの管理       |

---

## 5.2 コンテナ化方針

すべてのコンポーネントをコンテナ化しない。

以下の原則を採用する。

> アプリケーション層はコンテナ化し、ホストの状態やネットワークに密接に関係するサービスはホスト上でsystemd管理する。

### 5.2.1 コンテナで実行するコンポーネント

宅内ゲートウェイ用マシン上で、以下をDocker Composeにより実行する。

* VictoriaMetrics
* Grafana

### 5.2.2 ホスト上で実行するコンポーネント

以下はホスト上でsystemdサービスとして実行する。

#### AIエージェント用マシン

* Tailscale
* OpenSSH Server
* Node Exporter
* Process Exporterまたは代替プロセス監視サービス
* Claude Code等のAIエージェント本体

#### 宅内ゲートウェイ用マシン

* Tailscale
* OpenSSH Server
* Cloudflare Tunnel
* Cockpit
* Node Exporter
* Docker Engine
* Docker Compose

### 5.2.3 AIエージェントの実行環境

Claude Code等のAIエージェント本体は、原則としてホスト上で実行する。

プロジェクト固有の依存環境、ビルド環境、テスト環境は、必要に応じて以下へ分離する。

* Dockerコンテナ
* Dev Container
* プロジェクト専用コンテナ
* 一時的なテストコンテナ

---

## 5.3 リポジトリ管理方針

本システムに関する構成、設定、ドキュメント、ダッシュボードおよびテストは、単一のGitHubリポジトリにまとめる。

モノレポ方式を採用し、以下を同一PRで変更できるようにする。

* Exporter設定
* VictoriaMetrics設定
* Grafanaダッシュボード
* Grafanaデータソース設定
* アラートルール
* systemd unit
* Docker Compose
* ファイアウォール設定
* テスト
* 要件定義
* 設計書
* 運用手順書

独自Exporter等が将来、独立配布可能な製品またはOSSとなった場合に限り、別リポジトリへの分離を検討する。

---

# 6. システム構成

## 6.1 論理構成

```text
外部PC
├─ Tailscale
│  ├─ AIエージェント用マシンへのSSH接続
│  ├─ ゲートウェイ機へのSSH接続
│  ├─ ゲートウェイ機のCockpitへのアクセス
│  └─ Grafanaへのアクセス
│
└─ 必要に応じてCloudflare Access
   └─ Cloudflare Tunnel経由でGrafanaへアクセス

AIエージェント用マシン
├─ ホスト上
│  ├─ Claude Code等のAIエージェント
│  ├─ OpenSSH Server
│  ├─ Tailscale
│  ├─ Node Exporter
│  ├─ Process Exporterまたは代替監視サービス
│  └─ AIエージェント固有メトリクス出力機構
│
└─ 必要に応じたコンテナ
   ├─ プロジェクト開発環境
   ├─ ビルド環境
   ├─ テスト環境
   └─ MCPサーバー

宅内ゲートウェイ用マシン
├─ ホスト上
│  ├─ OpenSSH Server
│  ├─ Tailscale
│  ├─ Cloudflare Tunnel
│  ├─ Cockpit
│  ├─ Node Exporter
│  └─ Docker Engine
│
└─ Docker Compose
   ├─ VictoriaMetrics
   └─ Grafana
```

---

## 6.2 コンポーネント責務

| コンポーネント           | 配置先           | 実行方式           | 責務                |
| ----------------- | ------------- | -------------- | ----------------- |
| Claude Code等      | AIエージェント機     | ホスト            | AIエージェント処理        |
| Node Exporter     | 両マシン          | systemd        | OS・ハードウェアメトリクス公開  |
| Process Exporter  | AIエージェント機     | systemd        | プロセスグループ別メトリクス公開  |
| VictoriaMetrics   | ゲートウェイ機       | Docker Compose | メトリクス収集、保存、検索     |
| Grafana           | ゲートウェイ機       | Docker Compose | 可視化、アラート表示        |
| Cockpit           | ゲートウェイ機       | systemd        | ゲートウェイ機自身の管理      |
| OpenSSH Server    | 両マシン          | systemd        | リモート管理            |
| Tailscale         | 両マシン          | systemd        | 暗号化されたプライベート通信    |
| Cloudflare Tunnel | ゲートウェイ機       | systemd        | 必要に応じたGrafana外部公開 |
| Docker            | 両マシンまたは必要なマシン | systemd        | コンテナ実行基盤          |

---

# 7. スコープ

## 7.1 対象範囲

本システムの初期構築対象は以下とする。

* AIエージェント用マシンのシステムメトリクス収集
* AIエージェント関連プロセスの集約メトリクス収集
* ゲートウェイ用マシン自身のシステムメトリクス収集
* VictoriaMetrics自身のメトリクス収集
* Grafanaダッシュボード構築
* Tailscale経由のメトリクス収集
* 死活監視
* 基本的なリソースアラート
* メトリクス保持期間の管理
* Docker Composeによる監視アプリケーション管理
* systemdによるホストサービス管理
* GitHubモノレポによる構成管理
* CIによる設定ファイル検証
* 構築手順および復旧手順の文書化

## 7.2 対象外

初期構築では、以下を対象外とする。

* AIエージェント用マシンへのCockpit導入
* Cockpitマルチホスト機能
* Kubernetes
* VictoriaMetricsクラスタ構成
* 複数拠点の監視
* メトリクスデータの完全永続保証
* AIエージェント会話内容の収集
* プロンプト全文の収集
* ソースコード本文の収集
* APIキーまたは認証トークンの収集
* AIエージェントの自動停止
* リソース状況に応じた自動スケーリング
* Pコア／Eコアへの強制的なCPU固定
* Loki等のログ基盤
* 分散トレーシング
* OpenTelemetryによる詳細トレース
* GPU監視

対象外項目は、将来の拡張候補とする。

---

# 8. 機能要件

## 8.1 システムメトリクス収集

### FR-001 CPUメトリクス

両マシンについて、以下を収集できること。

* CPU全体使用率
* 論理CPUごとの使用率
* user
* system
* idle
* iowait
* irq
* softirq
* steal
* Load Average
* CPU Pressure Stall Information
* CPU動作周波数
* 取得可能な場合はCPU温度
* 取得可能な場合はサーマルスロットリング情報

### FR-002 メモリメトリクス

以下を収集できること。

* 総メモリ容量
* MemAvailable
* 使用中メモリ
* キャッシュ
* バッファ
* swap総容量
* swap使用量
* swap in
* swap out
* Memory Pressure Stall Information
* OOM Kill発生状況

### FR-003 ストレージメトリクス

以下を収集できること。

* ファイルシステム総容量
* 使用容量
* 空き容量
* 使用率
* inode使用率
* デバイス別読み込み量
* デバイス別書き込み量
* IOPS
* I/O処理時間
* I/O待ち時間の推定値
* I/O Pressure Stall Information

### FR-004 ネットワークメトリクス

以下を収集できること。

* 物理NICの送受信量
* Tailscaleインターフェースの送受信量
* パケット数
* パケットエラー
* パケットドロップ
* TCP接続状態
* ソケット使用状況

### FR-005 OSおよびサービス状態

以下を収集できること。

* uptime
* 起動時刻
* 総プロセス数
* 実行中プロセス数
* ファイルディスクリプタ使用量
* systemd unit状態
* 監視対象サービスの状態
* ホスト再起動の有無

---

## 8.2 AIエージェント関連プロセス監視

### FR-006 プロセスグループ監視

AIエージェント関連プロセスは、PID単位ではなく、論理プロセスグループ単位で監視すること。

初期グループ候補は以下とする。

* Claude Code
* Node.jsベースのAIエージェント関連処理
* PythonベースのAIエージェント関連処理
* Git
* ripgrep等のコード検索
* ビルドツール
* テストランナー
* MCPサーバー

### FR-007 プロセス識別

プロセス識別には、可能な範囲で以下を組み合わせる。

* コマンドライン
* 実行ユーザー
* 親プロセス
* systemd unit
* cgroup
* 起動時に付与する固定識別子

以下の実行ファイル名だけを条件として、AIエージェント関連プロセスと判定してはならない。

* `node`
* `python`
* `python3`

### FR-008 プロセスメトリクス

プロセスグループごとに、以下を確認できること。

* CPU使用時間
* CPU使用率
* RSSメモリ
* 仮想メモリ
* プロセス数
* スレッド数
* オープンファイル数
* 読み込みバイト数
* 書き込みバイト数
* 子プロセスを含む集約値

### FR-009 カーディナリティ制御

以下を原則として永続メトリクスのラベルに使用しないこと。

* PID
* 完全なコマンドライン
* ランダムなセッションID
* UUID
* タイムスタンプ
* 一時ファイル名
* 一時ディレクトリ
* Gitコミットハッシュ
* 動的なブランチ名
* ユーザー入力
* プロンプト本文

---

## 8.3 AIエージェント固有メトリクス

### FR-010 実行中エージェント数

現在実行中のAIエージェント数を確認できること。

### FR-011 実行結果

取得可能な範囲で、以下の集約値を確認できること。

* 総実行回数
* 正常終了回数
* 異常終了回数
* タイムアウト回数
* 平均実行時間
* 最大実行時間

### FR-012 プロジェクト単位集約

AIエージェントの稼働状況を、事前定義された固定のプロジェクト識別名単位で集約できること。

動的なパスまたは一時ディレクトリ名をプロジェクト識別子として使用してはならない。

### FR-013 機密情報除外

以下をメトリクスに含めてはならない。

* APIキー
* 認証トークン
* Cookie
* SSH秘密鍵
* プロンプト全文
* AIとの会話内容
* ソースコード本文
* 個人情報
* ファイル内容
* 環境変数の値

---

## 8.4 メトリクス収集・保存

### FR-014 収集対象

VictoriaMetricsは、以下のメトリクスを収集すること。

* AIエージェント用マシンのNode Exporter
* AIエージェント用マシンのProcess Exporterまたは代替Exporter
* AIエージェント固有メトリクス
* ゲートウェイ用マシンのNode Exporter
* VictoriaMetrics自身のメトリクス

### FR-015 通信経路

AIエージェント用マシンからのメトリクス収集は、Tailscaleネットワーク経由で行うこと。

### FR-016 収集間隔

初期の標準収集間隔は15秒とする。

必要に応じて、10秒から30秒の範囲で変更できること。

### FR-017 保持期間

初期保持期間は3か月を目安とする。

ただし、実際のディスク使用量に基づき、保持期間を変更可能であること。

### FR-018 ディスク容量監視

以下を監視できること。

* VictoriaMetricsの保存データ量
* ゲートウェイ機のディスク空き容量
* ディスク使用率
* データ増加率

### FR-019 データ消失時の独立性

監視データが消失しても、以下へ影響を与えないこと。

* AIエージェントの実行
* ソースコード
* Gitリポジトリ
* ビルド成果物
* テスト結果
* Cloudflare Tunnel
* Tailscale
* SSH

---

## 8.5 Grafanaダッシュボード

### FR-020 データソース

Grafanaは、VictoriaMetricsをPrometheus互換データソースとして利用すること。

### FR-021 システム概要画面

以下を1画面で確認できること。

* 両マシンのUP／DOWN
* CPU使用率
* メモリ使用率
* swap使用量
* ストレージ使用率
* Load Average
* PSI
* ネットワーク使用量
* AIエージェント実行数
* 現在発生中のアラート
* 主要サービスの状態

### FR-022 AIエージェント用マシン画面

以下を表示すること。

* CPU全体使用率
* 論理CPU別使用率
* CPUヒートマップ
* CPU周波数
* メモリ使用量
* MemAvailable
* swap使用量
* swap in／out
* CPU PSI
* Memory PSI
* I/O PSI
* NVMe読み書き量
* I/O待ち時間
* ネットワーク送受信量
* AIエージェント関連プロセスグループ別CPU
* AIエージェント関連プロセスグループ別メモリ
* AIエージェント関連プロセス数
* AIエージェント実行数
* OOM履歴
* 温度

### FR-023 ゲートウェイ用マシン画面

以下を表示すること。

* CPU使用率
* メモリ使用量
* MemAvailable
* swap使用量
* ストレージ使用率
* VictoriaMetricsコンテナのCPUおよびメモリ使用量
* GrafanaコンテナのCPUおよびメモリ使用量
* VictoriaMetrics保存データ量
* scrape成功率
* scrape失敗数
* tailscaled状態
* cloudflared状態
* Cockpit状態
* Docker状態

### FR-024 時間範囲

以下の表示期間を容易に切り替えられること。

* 直近15分
* 直近1時間
* 直近6時間
* 直近24時間
* 直近7日
* 直近30日

### FR-025 コミュニティダッシュボード

Grafanaコミュニティダッシュボードは参考として利用できる。

ただし、以下を検証せずに本番採用してはならない。

* メトリクス名
* `job`ラベル
* `instance`ラベル
* 変数
* 単位
* Grafanaバージョン
* Exporterバージョン
* データソース設定

---

## 8.6 アラート

### FR-026 死活監視

以下の停止を検知できること。

* AIエージェント用マシン
* AIエージェント用マシンのNode Exporter
* AIエージェント用マシンのProcess Exporter
* ゲートウェイ機のNode Exporter
* VictoriaMetrics
* Grafana
* tailscaled
* cloudflared

### FR-027 リソース警告

初期警告対象は以下とする。

| 対象              | 条件の目安                    |
| --------------- | ------------------------ |
| CPU             | 高使用率が一定時間継続              |
| Load Average    | CPUコア数に対する高負荷が一定時間継続     |
| MemAvailable    | 10%未満                    |
| swap            | swap in／outが一定時間継続       |
| ストレージ           | 空き容量15%未満                |
| inode           | 空きinode15%未満             |
| PSI             | CPU、メモリ、I/Oのstallが一定時間継続 |
| OOM             | OOM Killを検知              |
| 温度              | 設定した警告温度を超過              |
| scrape          | 取得失敗が一定時間継続              |
| VictoriaMetrics | データ書き込み失敗                |
| Docker          | 監視コンテナ停止                 |

具体的なしきい値は、初期運用後の実測値に基づいて調整する。

### FR-028 通知

初期構築では、Grafana上でアラート状態を確認できることを必須とする。

外部通知は将来、以下から選択可能とする。

* メール
* Slack
* Discord
* Webhook
* その他メッセージングサービス

---

## 8.7 リモート管理

### FR-029 AIエージェント用マシン

AIエージェント用マシンは、Tailscale経由のSSHで管理する。

Cockpitを使用しない。

### FR-030 ゲートウェイ用マシン

ゲートウェイ用マシンは、以下で管理する。

* Cockpit
* SSH

### FR-031 Grafanaアクセス

Grafanaへのアクセスは、原則としてTailscale経由とする。

Cloudflare Tunnel経由で公開する場合は、Cloudflare Access等の認証・認可を必須とする。

### FR-032 Cockpitアクセス

Cockpitは原則としてTailscale内に限定する。

Cockpitをインターネットへ直接公開してはならない。

---

# 9. 非機能要件

## 9.1 性能

### NFR-001 AIエージェント機の監視負荷

AIエージェント用マシン上の監視コンポーネントは、AIエージェント処理へ重大な性能低下を発生させてはならない。

通常時の監視コンポーネント合計CPU使用率は、平均1%未満を目標とする。

### NFR-002 ゲートウェイ機のメモリ

通常運用時に、ゲートウェイ機のMemAvailableが20%以上確保される状態を目標とする。

### NFR-003 基幹サービス優先

メモリ不足時には、以下のサービスを監視・可視化サービスより優先する。

1. tailscaled
2. cloudflared
3. sshd
4. Cockpit
5. Docker
6. VictoriaMetrics
7. Grafana

VictoriaMetricsおよびGrafanaには、必要に応じて以下を設定する。

* Dockerメモリ制限
* systemdによるDockerサービス制御
* OOM優先度
* 再起動ポリシー

### NFR-004 ダッシュボード応答

通常利用時に、主要ダッシュボードが概ね5秒以内に表示されることを目標とする。

---

## 9.2 可用性

### NFR-005 自動起動

以下はOS起動時に自動起動すること。

* OpenSSH Server
* Tailscale
* Node Exporter
* Process Exporter
* Docker
* VictoriaMetrics
* Grafana
* Cloudflare Tunnel
* Cockpit

### NFR-006 自動復旧

以下を満たすこと。

* systemdサービスは異常終了時に自動再起動する
* Dockerコンテナは異常終了時に自動再起動する
* Docker再起動後にVictoriaMetricsとGrafanaが自動起動する
* Tailscale復旧後にメトリクス収集が自動再開される

### NFR-007 起動順序

Tailscale IPへ直接bindするサービスは、tailscaledおよびネットワーク準備完了後に起動すること。

起動順序を安定して保証できない場合は、以下を採用する。

* 全インターフェースでlisten
* ホストファイアウォールでTailscale経由のみに制限
* Tailscale ACLで接続元を制限

---

## 9.3 セキュリティ

### NFR-008 暗号化通信

マシン間通信は、TailscaleのWireGuardベース暗号化ネットワーク経由で行うこと。

### NFR-009 外部公開禁止

以下をインターネットへ直接公開してはならない。

* Node Exporter
* Process Exporter
* VictoriaMetrics
* SSH
* Cockpit
* Docker API

### NFR-010 ファイアウォール

Exporterポートは、ゲートウェイ機からTailscale経由でのみアクセス可能とする。

以下を併用することが望ましい。

* UFWまたはnftables
* Tailscale ACL

### NFR-011 Grafana認証

Grafanaは匿名アクセスを無効化する。

Cloudflare Tunnel経由で公開する場合は、以下を適用する。

* Cloudflare Access
* Grafana認証
* HTTPS
* アクセス対象ユーザーの制限

### NFR-012 最小権限

各ホストサービスは、可能な限り専用system userで実行する。

Process Exporter等で追加権限が必要な場合は、systemd sandbox設定を適用する。

### NFR-013 Docker権限

GrafanaおよびVictoriaMetricsコンテナへ、不要な以下を渡してはならない。

* privileged
* ホストPID名前空間
* Docker socket
* `/proc`全体
* `/sys`全体
* ホストroot filesystem

### NFR-014 秘密情報管理

以下をGitHubリポジトリへコミットしてはならない。

* APIキー
* パスワード
* Cloudflare Tunnelトークン
* Tailscale auth key
* Grafana管理者パスワード
* SSH秘密鍵
* `.env`実体
* TLS秘密鍵

`.env.example`には、値を含めず変数名のみ記載する。

---

## 9.4 保守性

### NFR-015 構成管理対象

以下をGitHubリポジトリで管理する。

* Docker Compose
* VictoriaMetrics scrape設定
* Grafana provisioning
* GrafanaダッシュボードJSON
* Grafanaデータソース設定
* Process Exporter設定
* systemd unit
* アラートルール
* ファイアウォール設定例
* Ansibleまたは構築スクリプト
* CI設定
* 要件定義
* 設計書
* 実装計画
* 運用手順
* 復旧手順
* 受入テスト

### NFR-016 再構築性

新規Ubuntu Server環境に対して、リポジトリ内の設定および手順から監視環境を再構築できること。

### NFR-017 更新およびロールバック

VictoriaMetricsおよびGrafanaは、Dockerイメージのバージョンを明示的に固定する。

`latest`タグを本番構成で使用しない。

更新時は、以前のイメージタグへ戻すことでロールバックできること。

### NFR-018 永続データ

以下をホスト側の永続ボリュームへ保存する。

* VictoriaMetricsデータ
* Grafanaデータ
* Grafana provisioning
* Grafanaダッシュボード
* VictoriaMetrics設定

コンテナ削除によって設定および監視履歴が同時に消失しないこと。

---

## 9.5 拡張性

### NFR-019 監視ホスト追加

将来、追加のAIエージェント用マシンを監視対象へ追加できること。

### NFR-020 独自Exporter

将来、AIエージェント固有Exporterを独立開発できること。

独自Exporterが以下を満たす場合、別GitHubリポジトリへの分離を検討する。

* 独立したバージョン管理が必要
* バイナリまたはコンテナとして配布する
* 他の環境で再利用する
* OSSとして公開する
* 監視基盤と異なるリリースサイクルを持つ

### NFR-021 ログおよびトレース

将来、以下を追加可能な構成とする。

* Loki
* OpenTelemetry Collector
* Tempo
* その他ログ・トレース基盤

### NFR-022 GPU監視

将来GPUを追加した場合、GPU Exporterを追加できること。

---

# 10. Pコア／Eコアに関する要件

## 10.1 初期要件

Pコア／Eコア別の表示は、初期構築の必須要件としない。

論理CPU別使用率を取得し、必要性が確認された段階で追加する。

## 10.2 CPU番号

PコアおよびEコアの論理CPU番号を固定値として定義してはならない。

実機上で以下を参照して判定する。

* `lscpu`
* `/sys/devices/system/cpu/`
* CPU topology
* `core_type`

## 10.3 CPU affinity

初期状態ではLinuxカーネルのスケジューラーへ任せる。

以下によるCPU固定は、監視結果とベンチマークによって有効性を確認した後にのみ適用する。

* `taskset`
* systemd `AllowedCPUs`
* systemd `CPUWeight`
* cgroup CPU制御

---

# 11. データおよびラベル設計

## 11.1 推奨ラベル

以下の低カーディナリティなラベルを使用する。

```text
instance
job
host
role
agent_type
process_group
project
result
environment
```

## 11.2 使用禁止または制限対象

以下を原則としてラベルへ使用しない。

```text
pid
session_uuid
timestamp
full_command_line
prompt
file_path
temporary_directory
git_commit
dynamic_branch
user_input
raw_error_message
```

## 11.3 ホスト識別

`instance`または`host`には、ホストを一意に識別できる固定名称を使用する。

例：

```text
ai-agent-01
home-gateway-01
```

## 11.4 job名称

以下のような役割ベースの名称を使用する。

```text
node
process
agent-metrics
victoriametrics
```

## 11.5 セッション詳細

セッションごとの詳細情報が必要な場合、永続メトリクスラベルへ格納せず、将来導入するイベントログまたはトレースへ保存する。

---

# 12. GitHubリポジトリ要件

## 12.1 リポジトリ形式

単一のGitHubリポジトリによるモノレポとする。

リポジトリ名の候補は以下とする。

```text
ai-agent-observability
```

## 12.2 推奨ディレクトリ構成

```text
ai-agent-observability/
├── README.md
├── docs/
│   ├── requirements.md
│   ├── architecture.md
│   ├── implementation-plan.md
│   ├── operations.md
│   └── disaster-recovery.md
│
├── hosts/
│   ├── ai-agent/
│   │   ├── node-exporter/
│   │   ├── process-exporter/
│   │   ├── systemd/
│   │   ├── firewall/
│   │   └── scripts/
│   │
│   └── gateway/
│       ├── node-exporter/
│       ├── cloudflared/
│       ├── cockpit/
│       ├── systemd/
│       ├── firewall/
│       └── scripts/
│
├── monitoring/
│   ├── compose.yaml
│   ├── .env.example
│   ├── victoriametrics/
│   │   ├── prometheus.yml
│   │   ├── rules/
│   │   └── data/
│   │
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/
│       │   ├── dashboards/
│       │   └── alerting/
│       ├── dashboards/
│       └── data/
│
├── automation/
│   ├── ansible/
│   │   ├── inventory/
│   │   ├── roles/
│   │   └── playbooks/
│   └── scripts/
│
├── tests/
│   ├── configuration/
│   ├── connectivity/
│   ├── security/
│   └── acceptance/
│
├── Makefile
├── .gitignore
├── .editorconfig
└── .github/
    └── workflows/
```

永続データディレクトリはGit管理対象外とする。

## 12.3 同一PRでの整合性

以下の変更は、可能な限り同一PRで行う。

* Exporterメトリクス名の変更
* Process Exporterグループ名の変更
* VictoriaMetrics scrape設定変更
* Grafanaクエリ変更
* アラートルール変更
* ドキュメント変更
* テスト変更

## 12.4 CI要件

GitHub Actions等で、以下を検証する。

* YAML構文
* Docker Compose構文
* Prometheus互換設定
* アラートルール
* GrafanaダッシュボードJSON
* systemd unitの基本構文
* ShellCheck
* Ansible lint
* Markdown lint
* 秘密情報の混入
* 必須ファイルの存在
* ラベル名の整合性

---

# 13. Docker Compose要件

## 13.1 対象コンテナ

Docker Composeで以下を管理する。

* VictoriaMetrics
* Grafana

## 13.2 イメージタグ

コンテナイメージは、明示的なバージョンタグを使用する。

以下は禁止する。

```text
latest
main
nightly
```

## 13.3 再起動ポリシー

以下を設定する。

```yaml
restart: unless-stopped
```

または、同等の自動再起動設定を使用する。

## 13.4 永続化

VictoriaMetricsおよびGrafanaのデータは、ホスト側の永続ディレクトリまたはnamed volumeへ保存する。

## 13.5 ポート公開

VictoriaMetricsは原則としてホスト外へ公開しない。

Grafanaは原則として以下のいずれかとする。

* localhostでlistenし、Tailscaleまたはリバースプロキシから接続
* Tailscaleインターフェースでのみlisten
* ホストファイアウォールで接続元を制限

## 13.6 リソース制御

必要に応じて、GrafanaおよびVictoriaMetricsへ以下を設定する。

* メモリ上限
* CPU上限
* PID上限
* ログローテーション
* ヘルスチェック

ただし、VictoriaMetricsの内部メモリ設定を、プロセス全体の厳密なハード上限として扱わない。

---

# 14. 運用要件

## 14.1 日常運用

通常運用では、Grafanaのシステム概要画面を確認する。

異常がある場合に、各ホストまたはプロセスグループの詳細画面を確認する。

## 14.2 AIエージェント用マシンの管理

AIエージェント用マシンはSSHで操作する。

例：

```bash
ssh ai-agent-01
systemctl status node_exporter
systemctl status process_exporter
journalctl -u node_exporter
journalctl -u process_exporter
```

## 14.3 ゲートウェイ用マシンの管理

ゲートウェイ用マシンは、CockpitまたはSSHで管理する。

Docker Composeの操作は、SSHまたはCockpitのターミナルから行う。

## 14.4 月次確認

最低でも月1回、以下を確認する。

* ゲートウェイ機のディスク空き容量
* VictoriaMetrics保存データ量
* 時系列数
* 高カーディナリティラベルの有無
* Grafanaメモリ使用量
* VictoriaMetricsメモリ使用量
* コンテナログ容量
* アラート誤検知
* 未検知の障害
* ソフトウェア更新状況

## 14.5 更新

更新前に以下を実施する。

* 設定ファイルのGitコミット
* 永続データの必要なバックアップ
* リリースノート確認
* 破壊的変更確認
* ダッシュボード互換性確認
* ロールバック用イメージタグ確認

---

# 15. バックアップ要件

## 15.1 必須バックアップ

以下をGitHubリポジトリまたは別の安全な場所へ保存する。

* Docker Compose
* VictoriaMetrics設定
* Grafana provisioning
* GrafanaダッシュボードJSON
* アラートルール
* Process Exporter設定
* systemd unit
* ファイアウォール設定
* Ansibleまたは構築スクリプト
* 構築手順
* 復旧手順

## 15.2 監視データ

初期段階では、VictoriaMetricsの時系列データ自体を必須バックアップ対象としない。

監視履歴の保持が重要になった場合に、スナップショットおよび外部バックアップを追加する。

---

# 16. 障害時要件

## 16.1 ゲートウェイ機停止

ゲートウェイ機が停止しても、AIエージェント用マシン上のAIエージェント実行は継続できること。

停止中のメトリクスは保存されない。

## 16.2 VictoriaMetrics停止

VictoriaMetricsが停止しても、以下へ影響を与えないこと。

* AIエージェント
* Tailscale
* Cloudflare Tunnel
* SSH
* Cockpit
* Grafana以外のホストサービス

## 16.3 Grafana停止

Grafanaが停止しても、VictoriaMetricsによるメトリクス収集は継続すること。

## 16.4 Docker停止

Dockerが停止した場合、VictoriaMetricsおよびGrafanaは停止する。

ただし、以下は継続すること。

* Tailscale
* Cloudflare Tunnel
* SSH
* Cockpit
* Node Exporter

Docker復旧後、監視コンテナが自動起動すること。

## 16.5 Tailscale停止

Tailscale停止中は、マシン間のメトリクス収集および外部PCからの管理アクセスが失敗する。

復旧後、手動操作なしで収集および接続が再開できること。

## 16.6 ディスク容量不足

ゲートウェイ機の空き容量が設定値を下回った場合、アラートを発生させる。

監視データによってOS領域を完全に使い切らないようにする。

---

# 17. 受入条件

### AC-001 基本メトリクス

Grafana上で、両マシンのCPU、メモリ、ストレージ、ネットワーク情報を確認できること。

### AC-002 プロセス監視

Claude Code等のAIエージェント関連プロセスについて、グループ単位のCPU、メモリおよびプロセス数を確認できること。

### AC-003 ゲートウェイ監視

ゲートウェイ機自身のリソースおよび主要サービス状態を確認できること。

### AC-004 Tailscale収集

VictoriaMetricsが、Tailscale経由でAIエージェント用マシンのメトリクスを収集できること。

### AC-005 外部公開制限

Node Exporter、Process Exporter、VictoriaMetrics、SSHおよびCockpitへ、インターネットから直接接続できないこと。

### AC-006 SSH管理

外部PCからTailscale経由でAIエージェント用マシンへSSH接続できること。

### AC-007 Cockpit役割

Cockpitがゲートウェイ用マシン上で動作すること。

AIエージェント用マシンにCockpitがインストールされていないこと。

### AC-008 コンテナ構成

VictoriaMetricsおよびGrafanaがDocker Composeで起動すること。

Node ExporterおよびProcess Exporterがホスト上のsystemdサービスとして起動すること。

### AC-009 再起動耐性

両マシンの再起動後、必要なサービスおよびコンテナが自動起動し、メトリクス収集が再開されること。

### AC-010 監視負荷

監視コンポーネントによって、AIエージェント実行に明確な性能低下が発生しないこと。

### AC-011 ゲートウェイ安定性

VictoriaMetricsおよびGrafana稼働中も、Tailscale、Cloudflare Tunnel、SSHおよびCockpitが安定して動作すること。

### AC-012 アラート

監視対象Exporterまたはコンテナを意図的に停止した際に、Grafana上で異常を検知できること。

### AC-013 ディスク監視

ゲートウェイ機の空き容量およびVictoriaMetrics保存容量をGrafanaで確認できること。

### AC-014 機密情報

メトリクス、GrafanaダッシュボードおよびGitHubリポジトリに、APIキー、認証トークン、プロンプト全文、ソースコード本文またはSSH秘密鍵が含まれていないこと。

### AC-015 モノレポ

構成、ダッシュボード、ドキュメントおよびテストが、単一GitHubリポジトリで管理されていること。

### AC-016 CI

Pull Request作成時に、主要な設定ファイル、Docker Compose、ダッシュボードおよび秘密情報混入の自動検証が実行されること。

---

# 18. 導入フェーズ

## Phase 1：リポジトリおよび基盤準備

* GitHubモノレポ作成
* ディレクトリ構成作成
* `.gitignore`作成
* `.env.example`作成
* CIの最小構成作成
* Tailscale接続確認
* SSH接続確認

## Phase 2：ホストメトリクス収集

* 両マシンへNode Exporter導入
* systemd unit作成
* ファイアウォール設定
* Tailscale経由の接続確認
* Node Exporterの低負荷確認

## Phase 3：監視バックエンド構築

* ゲートウェイ機へDocker導入
* Docker Compose作成
* VictoriaMetrics導入
* Grafana導入
* 永続ボリューム設定
* リソース制限設定
* 自動起動確認

## Phase 4：基本ダッシュボード

* Grafanaデータソース設定
* 両ホストの基本ダッシュボード作成
* ゲートウェイ監視画面作成
* VictoriaMetrics自己監視
* Dockerコンテナ監視

## Phase 5：AIエージェントプロセス監視

* Process Exporterまたは代替方式の導入
* プロセス識別ルール作成
* 子プロセス集約確認
* カーディナリティ確認
* AIエージェント詳細画面作成

## Phase 6：AIエージェント固有メトリクス

* 実行ラッパーまたはhookの設計
* 実行数の取得
* 成功／失敗数の取得
* 実行時間の取得
* プロジェクト単位集約
* 機密情報除外確認

## Phase 7：アラートおよび運用整備

* 死活監視
* CPU／メモリ／ディスクアラート
* OOM検知
* PSIアラート
* scrape失敗検知
* 運用手順作成
* 復旧手順作成
* 受入試験

## Phase 8：任意の高度化

必要な場合のみ実施する。

* Pコア／Eコア別表示
* systemd scopeまたはcgroupによるエージェント分離
* Loki導入
* OpenTelemetry導入
* GPU監視
* 外部アラート通知
* 独自Exporterの分離

---

# 19. 技術選定

| 分類          | 採用方針                                      |
| ----------- | ----------------------------------------- |
| ホストメトリクス    | Prometheus Node Exporter                  |
| プロセス監視      | Process Exporterを初期候補とし、必要に応じてcgroup方式へ変更 |
| メトリクス保存     | VictoriaMetrics single-node               |
| 可視化         | Grafana                                   |
| コンテナ管理      | Docker Compose                            |
| ゲートウェイ管理    | Cockpit                                   |
| AIエージェント機管理 | OpenSSH                                   |
| プライベート通信    | Tailscale                                 |
| 任意の外部公開     | Cloudflare TunnelおよびCloudflare Access     |
| 構成管理        | GitHubモノレポ                                |
| 自動検証        | GitHub Actions等のCI                        |

VictoriaMetricsの採用は、ゲートウェイ機のメモリおよびストレージ制約を考慮したものである。

ただし、Prometheusとの比較において、常に一定割合だけメモリまたはディスク使用量が少ないことを保証するものではない。

実際のリソース消費は、以下に基づいて評価する。

* 時系列数
* scrape間隔
* 保持期間
* ラベル数
* プロセス生成頻度
* Grafanaクエリ負荷
* 実測メモリ使用量
* 実測ディスク増加率

---

# 20. 確定事項

以下を最終決定事項とする。

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

---

# 21. 実装設計時に確定する事項

以下は要件としての方針を確定済みだが、具体的な実装方法は基本設計または詳細設計で決定する。

1. Process Exporterの具体的なグループ定義
2. cgroupまたはsystemd scopeを併用するか
3. AIエージェント固有メトリクスの出力方法
4. Grafanaの具体的なダッシュボードレイアウト
5. Grafana Alertingの具体的なしきい値
6. VictoriaMetricsの実際の保持期間
7. Dockerコンテナの具体的なメモリ上限
8. Grafanaの認証方式
9. Cloudflare Tunnel経由のGrafana公開を行うか
10. 温度監視に利用するセンサーおよびカーネルモジュール
11. Ansibleを採用するか、シェルスクリプトを採用するか
12. AIエージェントのプロジェクト識別方法
13. 外部アラート通知先
14. ログ基盤の将来導入時期

---

# 22. 完了定義

以下をすべて満たした時点で、初期構築を完了とする。

* 両マシンの基本システムメトリクスをGrafanaで確認できる
* AIエージェント関連プロセスのCPUおよびメモリ使用量を確認できる
* ゲートウェイ機自身と監視基盤の状態を確認できる
* メトリクス収集がTailscale経由に限定されている
* AIエージェント用マシンをSSHで管理できる
* ゲートウェイ用マシンをCockpitおよびSSHで管理できる
* AIエージェント用マシンにCockpitが導入されていない
* VictoriaMetricsおよびGrafanaがDocker Composeで動作している
* Exporterがホスト上のsystemdサービスとして動作している
* 両マシンの再起動後に監視が自動復旧する
* ゲートウェイ機の基幹サービスが安定稼働している
* 基本的な死活監視およびリソース警告が機能する
* 機密情報がメトリクスおよびGitHubリポジトリに含まれていない
* 構成、設定、ドキュメントおよびテストが単一GitHubリポジトリで管理されている
* Pull Request時に設定の自動検証が実行される
* 構築手順、運用手順および復旧手順が文書化されている

