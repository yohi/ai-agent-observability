# ダッシュボード

最終更新: 2026-07-29 19:59

## 🐸 Frog / ストリーク
| 項目 | 値 |
|------|-----|
| 今日のFrog | subtask_001b（docs/architecture.md執筆） → **撃破済み** |
| Frog状態 | 🐸✅ 撃破済み |
| ストリーク | - |
| 今日の完了 | 21/23 |
| VFタスク残り | - |

## 🔄 進行中

- **cmd_001** — AIエージェント実行環境 監視・可視化システム → **secret-scan網の最終調整**
  - フェーズ1・2（基本設計・設計書・計画書）→ **完了**。Phase 1主要4成果物（ci.yml/operations.md/secret-scan.yml/bootstrap.sh）→ **全完了・軍師QC PASS**
  - QC-014・015・025・027・028（走査範囲・検出規則・ID衝突・死んだ除外・サフィックス検出漏れ）すべてRESOLVED
  - **【追補中・warning】QC-029**: QC-028是正案（`[a-z0-9_]*`）自体が語尾を無制限に延長し過検知6件を生むことが軍師実測で判明（軍師自身の是正案の欠陥、足軽2号に瑕疵なし）。案B（`(_{1,2}(file|path|value|key|env))?`）へ差し替え。追補発行済み(subtask_002j)
  - 完了後Phase 2発行へ（QC-006のチェックリスト反映が必要）
- **SEC-001（ai-agent-observability側）** → QC-028・QC-029・QC-035（subtask_002k）すべて解消。軍師実測でリモートはbyte-identicalと確認、CI全27step success。**ai-agent-observability側は完成**
- **【技術的完了・殿の裁可待ちのみ】SEC-001（本リポジトリ側）**: QC-036・QC-038すべて解消。軍師がclone上で6ファイル（`.gitignore`/`.gitleaks.toml`/`.gitleaksignore`/`secret-scan.yml`/`context/ai-agent-observability.md`/`docs/security-issues.md`）を実際にcommitしCIが緑（exit code 0）かつ検出力健全（実形式資格情報8種の探針で8/8検出）であることまで実測済み。**新規critical QC-039を発見**: 分割commitで`.gitleaks.toml`を欠くと、CIは緑のまま検出力が8分の1に落ちる「偽の緑」——AWS・GitHub PAT・**Tailscale auth key**・**Cloudflare Tunnel token**・Discord webhookが素通りする（原因: HEAD版に`[extend] useDefault = true`が無く既定ルール群が読まれない）。是正すべきコードは無く、**SEC-002上申に「6ファイルは同一コミット必須、とりわけ.gitleaks.tomlを欠くな」の一文を加えるのみ**。技術的障壁はこれで消滅、残るは殿の裁可のみ

## ✅ 完了

- 2026-07-29 subtask_001a〜001h（足軽1〜6号）: cmd_001フェーズ1・2・新リポジトリ移行 全完了。軍師QC全件PASS
- 2026-07-29 subtask_sec001b・subtask_sec003（ashigaru7）: SEC-001管理体制の確立、git追跡対象化完了
- 2026-07-29 QC-011・QC-012是正（家老直接対応）: context/ai-agent-observability.md・docs/security-issues.mdを新リポジトリ基準へ更新
- 2026-07-29 subtask_002a・002d・002e・002f2・002g・002h（足軽1・2・3・4号）: Phase 1主要4成果物完成＋QC-025/027是正、軍師QC全件PASS

## 🚨 要対応

1. ~~OQ-001〜003・QC-001/004/005/008/SEC-003・QC-011/012・QC-013・QC-014・QC-015・QC-017〜022・QC-025・QC-027・QC-028・QC-029・QC-030・QC-031・QC-035・QC-036・QC-038~~ → ✅**全解決済み**。
2. **【緊急・critical・要記録のみ】QC-039**: `.gitleaks.toml`を欠く分割commitは、CIをexit code 0（緑）にしたまま検出力を8分の1に落とす「偽の緑」——AWS/GitHub PAT/Tailscale auth key/Cloudflare Tunnel token/Discord webhookが素通りする（軍師実測: 探針8/8→1/8）。原因はHEAD版に`[extend] useDefault = true`が無いこと。**是正すべきコードは存在しない**——SEC-002上申（上記4項）に既に反映済み。
3. **【制約記録・要反映】QC-033**: gitleaksはRE2エンジンのため否定先読み`(?!...)`使用不可（設定書いた瞬間にpanic、検出漏れより危険）。軍師自身が実測で踏んだ。QC-023作法テンプレートへの組込みが必要。
4. **【技術的障壁は解消・裁可のみ待ち】SEC-002**: 本リポジトリのoriginがyohey-w（pull専用）のため、SEC-001の全成果（`.gitignore`/`.gitleaks.toml`/`.gitleaksignore`/`secret-scan.yml`）とSEC-003の2ファイル（`context/ai-agent-observability.md`/`docs/security-issues.md`）、計6ファイルがpush先を持たず未コミットのまま宙に浮いている（`git checkout`一発で全損するリスクあり）。**殿の裁可が下りcommitする際は、この6ファイルを必ず同一コミットに含めること。とりわけ`.gitleaks.toml`を欠いた分割commitは、CIを緑にしたまま検出力を8分の1に落とす「偽の緑」を生む**（Tailscale auth key・Cloudflare Tunnel tokenが素通りする実測済みの危険。QC-039）。軍師がcommit済みclone上でCIが緑かつ検出力健全（探針8/8検出）であることまで実測済みのため、**技術的障壁はこれで消滅した**。残るは殿の裁定のみ（forkの検討等）。
5. **【CI構築時に反映・QC-026】検査機構自体の生存を検査していない**: QC-025・027・028・029・030・031・035・036はいずれも「規則が届かない／届きすぎる／除外が広すぎる／狭めた拍子に届かなくなる／fingerprint方式が要る」形だった。加えてQC-033で「設定が起動すらしない」形も判明。`tests/security/`への(a)実物形式ダミー・期待RuleID対応表、(b)ネガティブケース表、(c)除外の救うべき/救ってはならぬ対比表、(d)秘密隣接サフィックス検出表、(e)設定起動可否検査、(f)除外の死活検査、を**対で**恒久配置することをPhase 2で求める。
6. **【info・Phase 2検討事項】QC-024**: bootstrap.shの一時ファイルはTMPDIR依存。緊急性なし。
7. **【Phase 2タスク発行時に対応】QC-006**: 成果物60件中11件が計画書のPhase未割当。`hosts/gateway/systemd/*.service.d/oom.conf`（NFR-003）はPhase 2で明示すること。
8. **軽微**: `/tmp/aio-migrate`（共有クローン、危険なため以後使用禁止）が残置。放置または殿が手動削除の判断を。足軽3号のskill_candidate（CLAUDE.mdへBatch Processing Protocol追加）・足軽5号のskill_candidate（除外regexの終端境界・構造最小単位化の作法、gitleaksの`regexTarget=match`必須の知見）が未裁定のまま残る。QC-034・QC-037（死んだ除外、計6行、info）も次善課題として蓄積中。
9. **【運用改善提案・要裁定】gunshi_report.yaml単一ファイル上書き方式**: これまでに17本の報告が上書き消失（本報告で5例目の実害——QC-031/032の原文とQC-029の原文が上書きで失われ、家老がQC-036の根拠を遡って検証できない状態）。`queue/reports/gunshi/{task_id}.yaml`等への分割案が軍師・足軽3号双方から提案されている（instructions改訂を伴うため殿裁定が必要）。

## 検証原則（本日の教訓・恒久ルール）

**「CIが成功した」は「検査された」を意味しない。「規則を書いた」は「規則が効く」を意味しない。**
検査・監視・アラート機構を作るタスクの完了条件には、必ず「機構が実際に検出/発火することを試験で示す」ことを含めること。conclusion: successや設定ファイルの存在だけで合格と判断してはならない。

**秘密情報の露出経路は4つ**（リポジトリ・コマンドライン引数/プロセス環境・ディスク残留・ログ出力）。QC-020/021は「プロセス表の露出を塞いだ代わりにディスク残留を開けた」事例——受け渡し方式を変更する際は変更前後で4経路すべてを比較し、総量が減っていることを確認する。

**シェルスクリプト成果物には動的検査を完了条件に含める**（QC-023）。`shellcheck`・`bash -n`は`trap`内のlocal変数の可視域を追跡しない。外部コマンドをスタブに置き換えて実際に実行し、正常系exit 0・異常系で残骸なしを実際の出力とともに報告させる。「実行するな」制約とは矛盾しないことを明記しないと足軽は動的検査自体を省略する。

**軍師のrecommended_fixに具体コードが含まれる場合、家老も簡易的に妥当性を検討する**。検証されていない修正案がそのままタスクYAMLに転記されると、指摘した欠陥より深い新欠陥を生む（QC-020/021の直接原因）。

## 運用上の注記（インシデント記録・恒久化）

2026-07-29、`queue/reports/gunshi_report.yaml`が軍師のタスク完了ごとに上書きされる運用のため、
軍師の基本設計報告（gunshi_design_001）がQC報告2件により2度上書き消失した。足軽2号・3号が
着手前にこれを発見し、捏造禁止規則に従って作業を保留・報告した判断は適切だった（実害なし）。
家老がタスク発行時に読んでいた原文を`context/ai-agent-observability.md`へ機械的に復元し、
以後は同ファイルを唯一の情報源とする運用に切替済み。

軍師からも同様の運用改善提案あり: 「恒久価値のある設計報告は、軍師が`docs/`や`context/`へ
直接書ける経路を用意するか、家老が受信直後に転記する運用を正式手順化すべき」。今回は家老の
事後対応で切り抜けたが、構造的な脆弱性であるため今後も同型の事故が起きうる。恒久的な
instructions改訂の要否は殿のご判断を仰ぐ価値がある論点。

## スキル化候補

- **足軽3号提案（軍師支持）**: 「1ワーカー1ファイル上書き方式のreport YAMLは重要な決定内容を
  消失させる。家老が受信時点で`context/{project}.md`へ即時転記する運用をテンプレート化する」。
  今回のインシデントで実証済みの必要性。殿のご承認を要する（instructions改訂を伴うため）。
