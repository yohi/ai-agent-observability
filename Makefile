.PHONY: lint test up down validate bootstrap apply

## 設定ファイル群のlintを実行する（YAML/Compose/ShellCheck/Ansible lint/Markdown lint）
lint:
	@echo "未実装: lint ターゲット（後続タスクで実装）"

## tests/ 配下の検証スクリプトを実行する
test:
	@echo "未実装: test ターゲット（後続タスクで実装）"

## monitoring/ の Docker Compose スタックを起動する
up:
	@echo "未実装: up ターゲット（後続タスクで実装）"

## monitoring/ の Docker Compose スタックを停止する
down:
	@echo "未実装: down ターゲット（後続タスクで実装）"

## Compose/Prometheus等の設定構文を検証する
validate:
	@echo "未実装: validate ターゲット（後続タスクで実装）"

## Tailscale導入・SSH鍵配置等のブートストラップを実行する
bootstrap:
	@echo "未実装: bootstrap ターゲット（後続タスクで実装）"

## Ansible playbook を適用する
apply:
	@echo "未実装: apply ターゲット（後続タスクで実装）"
