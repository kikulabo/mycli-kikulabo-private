# TODO

進捗管理・セッション再開用。設計の正本は [CONCEPT.md](./CONCEPT.md)。

セッション再開時はまずこのファイルを見る。

---

## 🔄 次にやること (Immediate)

**ここから再開**: フェーズ 1 から順番に進める。

1. [x] `mise.toml` を作成する
2. [x] `mise install` でツールをインストールする（`mise lock` で `mise.lock` も生成）
3. [x] Go モジュールの初期化（`github.com/celestial-observability/mycli-kikulabo-private`）
4. [x] 依存ライブラリの追加・`go mod tidy`
5. [x] `.gitignore` を作成する
6. [x] `.golangci.yaml` を作成する
7. [x] ディレクトリ作成（`cmd/mycli` / `internal/cmd` / `internal/tracing` / `scripts` / `.github/workflows`）
8. [x] `LICENSE` を追加する

---

## 📋 その後の作業順 (Near-term)

### フェーズ 1: エントリーポイントだけで動かす

- [x] `scripts/e2e.sh` を作成する（`mycli --help` の検証のみ）
- [x] `bash scripts/e2e.sh` で FAIL を確認する
- [x] `Makefile` を作成する
- [x] `compose.yaml` を作成する（Jaeger サービスを定義する）
- [x] `cmd/mycli/main.go` を作成する（サブコマンドなし）
- [x] `make e2e` で PASS を確認する
- [x] `make lint` で PASS を確認する
- [x] `make fmt` を実行して差分が出ないことを確認する

### フェーズ 2: hello サブコマンドを追加する

- [x] `scripts/e2e.sh` に hello の検証を追加する（テストファースト）
  - `mycli hello` の exit 0 を検証する
  - `mycli hello` の stdout に `Hello, World!` が含まれることを検証する
- [x] `bash scripts/e2e.sh` で hello のケースが FAIL を確認する
- [x] `internal/cmd/hello.go` を作成する（`fmt.Println("Hello, World!")`）
- [x] `cmd/mycli/main.go` に `HelloCmd` を追加する
  - `kong.BindFor[context.Context](ctx)` を `kong.Parse` に渡す
- [x] `make e2e` で PASS を確認する
- [x] `make lint` で PASS を確認する

### フェーズ 3: OTel 計装を追加する

- [x] `scripts/e2e.sh` に OTel の検証を追加する（テストファースト）
  - スクリプト先頭に `START_US` を記録する（Jaeger API でのフィルタリング用）
  - `run_cmd_otlp` ヘルパーを追加する（`MYCLI_TRACES_EXPORTER=otlp MYCLI_OTLP_ENDPOINT=... OTEL_RESOURCE_ATTRIBUTES=''`）
  - コマンドタイムアウトを `perl -e 'alarm N; exec @ARGV'` で実装する（macOS 互換）
  - Jaeger 起動処理を追加する（mise 優先・Docker フォールバック）
  - `expect_trace_span_names` / `expect_trace_status_ok` ヘルパーを追加する
  - テストケースを追加する（CONCEPT.md の一覧参照）
- [x] `bash scripts/e2e.sh` で OTel のケースが FAIL を確認する
- [x] `internal/tracing/tracer.go` を作成する（`Tracer()` アクセサ）
- [x] `internal/tracing/span.go` を作成する（`SetSpanError()` ユーティリティ）
- [x] `internal/tracing/init.go` を作成する（TracerProvider・Shutdown・エクスポーター切り替え）
- [x] `internal/cmd/hello.go` に Span を追加する
- [x] `cmd/mycli/main.go` に OTel 初期化・main Span を追加する
- [x] `make e2e` で PASS を確認する
- [x] `make lint` で PASS を確認する

### フェーズ 4: リリースの整備

- [x] `mise.ci.toml` を作成する（`jaeger` のバージョンを固定する）
- [x] `MISE_ENV=ci mise install` を実行して `mise.ci.lock` を生成する
- [x] `renovate.json5` を作成する
  - 対象: `docker-compose`・`github-actions`・`mise`
  - クールダウン: `minimumReleaseAge: "7 days"`
- [x] `.goreleaser.yaml` を作成する（version: 2）
  - `goos: [darwin]`・`goarch: [amd64, arm64]`
  - archives の `files` に `LICENSE` を含める
- [x] `.github/workflows/ci.yaml` を作成する
  - `MISE_YES=1` を設定する
  - `lint` / `test` / `e2e` の 3 ジョブを定義する
  - e2e ジョブでは `MISE_ENV=ci` を設定して jaeger を使えるようにする
- [x] `.github/workflows/release.yaml` を作成する
  - トリガー: `v*` タグ push
  - goreleaser v2 を実行する

---

## ✅ 解決済み (Decisions Log)

新しい決定は上に追記。

- **2026-06-13** e2e.sh のコマンドタイムアウトは `perl -e 'alarm N; exec @ARGV'` で実装。macOS に GNU timeout がないため
- **2026-06-13** `OTEL_RESOURCE_ATTRIBUTES=''` をテスト時に空で上書き。Jaeger のトレースにノイズが混入しないため
- **2026-06-13** `internal/tracing/` を `init.go` / `tracer.go` / `span.go` の 3 ファイルに分割。op-vault 踏襲
- **2026-06-13** ツール管理は mise。`mise.toml`（開発）と `mise.ci.toml`（CI・jaeger）を分離する。`lockfile = true` で再現性を担保
- **2026-06-13** shfmt で `scripts/e2e.sh` をフォーマットする。`sh.fmt` ターゲットで実行
- **2026-06-13** Renovate で依存関係を自動更新。`docker-compose`・`github-actions`・`mise` を対象に 7 日クールダウン
- **2026-06-13** サブコマンドの置き場所は `internal/cmd/`。kong エコシステムで `internal/cli/`（op-vault）と `internal/cmd/`（記事）の両方が存在するが本プロジェクトは `internal/cmd/` を採用
- **2026-06-13** goreleaser のリリース対象は `darwin` のみ。本の読者が macOS 前提のため
- **2026-06-13** エントリーポイントは `cmd/mycli/main.go`。`main()` は `os.Exit(run())` のみ、処理は `run() int` に委譲する（op-vault 踏襲）
- **2026-06-13** OTel エクスポーターは環境変数 `MYCLI_TRACES_EXPORTER` で切り替える（`none` / `stdout` / `otlp`）
- **2026-06-13** `sdktrace.WithBlocking()` で同期 flush にする。短命プロセスの Span 欠落を防ぐため
- **2026-06-13** linter は golangci-lint v2。op-vault の `.golangci.yaml` をベースに採用。`shellcheck` で `scripts/e2e.sh` も検証する
