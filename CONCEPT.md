# CONCEPT: mycli-XXXX

## 目的

技術同人誌「OTel Native なオレオレ CLI ツールを作ってみよう」の素振り用リポジトリ。
`mycli hello` で Hello World を出力するところから始め、OTel 対応 CLI の構築を段階的に示す。

## ディレクトリ構成

op-vault を参考にした構成。（参考: https://github.com/sunakan/op-vault）

```
mycli-XXXX/
├── cmd/
│   └── mycli/
│       └── main.go          # エントリーポイント・OTel 初期化・kong.Parse
├── internal/
│   ├── cmd/
│   │   └── hello.go         # HelloCmd + Span
│   └── tracing/
│       ├── init.go          # TracerProvider の初期化と Shutdown
│       ├── tracer.go        # Tracer() アクセサ
│       └── span.go          # SetSpanError() などのユーティリティ
├── scripts/
│   └── e2e.sh               # E2E テスト
├── .github/
│   └── workflows/
│       ├── ci.yaml
│       └── release.yaml
├── compose.yaml              # Jaeger（Docker フォールバック用）
├── .golangci.yaml            # golangci-lint v2 設定
├── .goreleaser.yaml
├── .gitignore
├── LICENSE
├── Makefile
├── mise.toml                 # 開発ツール管理（golangci-lint・shfmt・shellcheck）
├── mise.ci.toml              # CI ツール管理（jaeger）
├── mise.lock                 # mise ロックファイル
├── mise.ci.lock              # CI 用 mise ロックファイル
├── renovate.json5            # 依存関係自動更新
├── go.mod
└── go.sum
```

### 設計方針

- `cmd/mycli/main.go` はエントリーポイントのみ。`run() int` に処理を委譲し `os.Exit` する
- サブコマンドの実装は `internal/cmd/` に集約する
- OTel の初期化・Shutdown は `internal/tracing/` に集約する

## ツール管理（mise）

開発ツールは mise で管理し再現性を担保する。

| ファイル | 管理するツール |
|---|---|
| `mise.toml` | `golangci-lint`・`shfmt`・`shellcheck` |
| `mise.ci.toml` | `jaeger`（CI のみ） |

`[settings] lockfile = true` を設定し `mise.lock` / `mise.ci.lock` を生成する。

## 使用ライブラリ

| ライブラリ | 用途 |
|---|---|
| github.com/alecthomas/kong | CLI フレームワーク |
| go.opentelemetry.io/otel | OTel API |
| go.opentelemetry.io/otel/trace | Tracer・Span インターフェース |
| go.opentelemetry.io/otel/sdk | TracerProvider 実装 |
| go.opentelemetry.io/otel/exporters/stdout/stdouttrace | 開発用 stdout エクスポーター |
| go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp | 本番用 OTLP エクスポーター |

## OTel 設計

### エクスポーターの切り替え

| 環境変数 `MYCLI_TRACES_EXPORTER` | 動作 |
|---|---|
| 未設定 または `none` | トレース無効（デフォルト） |
| `stdout` | stderr に JSON 出力（開発用） |
| `otlp` | OTLP エンドポイントへ送信（本番用） |

`stdout` が stderr に書く理由: コマンドの stdout を汚さないため。

### 短命プロセス問題への対処

CLI は実行後すぐに終了するため、非同期バッチャーだとバッファが flush される前に終了して Span が失われる。
`sdktrace.WithBatcher(exp, sdktrace.WithBlocking())` で同期 flush にする。

### Span 構成

```
main          ← main.go で作成。コマンド全体を囲む
└── hello     ← hello.go で作成。サブコマンドの処理を囲む
```

### internal/tracing/ の分割方針

| ファイル | 役割 |
|---|---|
| `init.go` | TracerProvider の初期化・Shutdown・エクスポーター切り替え |
| `tracer.go` | `Tracer()` アクセサ（`otel.Tracer("mycli")` を返す） |
| `span.go` | `SetSpanError()` などのユーティリティ |

## コマンド仕様

```
mycli hello   # 標準出力に "Hello, World!" を出力して終了
```

## E2E テスト設計

### 必要ツール

| ツール | 用途 | 入手方法 |
|---|---|---|
| `jq` | Jaeger API のレスポンス（JSON）をパース | `brew install jq` |
| `jaeger` | トレースバックエンド | `mise install`（`mise.ci.toml`） |
| `docker` | Jaeger の Docker フォールバック | Docker Desktop |

### Jaeger の起動戦略

mise 優先・Docker フォールバック（op-vault と同じ戦略）。

1. `mise exec -- jaeger` が使えれば直接起動してバックグラウンドで動かす
2. 使えなければ `docker compose up -d`（`compose.yaml` の jaeger サービス）で起動する
3. e2e 終了時に `cleanup` トラップで Jaeger を停止する

### Jaeger のポート

| ポート | 用途 |
|---|---|
| `16686` | Jaeger UI・トレース取得 API |
| `4318` | OTLP HTTP エンドポイント |

### e2e.sh の細部

- **コマンドタイムアウト**: macOS に GNU `timeout` がないため `perl -e 'alarm N; exec @ARGV'` で代替する
- **`OTEL_RESOURCE_ATTRIBUTES=''`**: テスト時にリソース属性のノイズを排除するため空で上書きする
- **`START_US`**: Jaeger API でトレース取得を「このテスト開始以降」に絞るための Unix マイクロ秒タイムスタンプ

### ヘルパー関数

| 関数 | 役割 |
|---|---|
| `run_cmd <args...>` | エクスポーターなしでコマンドを実行し stdout/stderr を変数に格納する |
| `run_cmd_otlp <args...>` | `MYCLI_TRACES_EXPORTER=otlp MYCLI_OTLP_ENDPOINT=... OTEL_RESOURCE_ATTRIBUTES=''` でコマンドを実行する |
| `expect_exit_code <code> <説明>` | 直前の終了コードを検証する |
| `expect_stdout_contains <str> <説明>` | stdout に文字列が含まれるか検証する |
| `expect_stderr_contains <str> <説明>` | stderr に文字列が含まれるか検証する |
| `expect_trace_span_names <names> <説明>` | Jaeger API から取得したトレースに Span 名が存在するか検証する |
| `expect_trace_status_ok <説明>` | Span の `otel.status_code` が `OK` であるか検証する |

### テストケース一覧

| シナリオ | 検証内容 |
|---|---|
| `mycli --help` | exit 0・stdout に `mycli` を含む |
| `mycli hello` | exit 0・stdout に `Hello, World!` を含む |
| `MYCLI_TRACES_EXPORTER=otlp mycli hello` | exit 0・Jaeger に `main` と `hello` の Span が存在する |
| `MYCLI_TRACES_EXPORTER=otlp mycli hello` | Span の `otel.status_code` が `OK` |
| `MYCLI_TRACES_EXPORTER=invalid mycli hello` | exit 1・stderr に `unknown MYCLI_TRACES_EXPORTER` を含む |
| `MYCLI_TRACES_EXPORTER=otlp`（ENDPOINT 未設定）`mycli hello` | exit 1・stderr に `MYCLI_OTLP_ENDPOINT is required` を含む |

## Lint 設計

### Go（golangci-lint v2）

`.golangci.yaml` で管理する。op-vault の設定をベースにする。

| 項目 | 設定値 |
|---|---|
| フォーマッター | `gofumpt`・`goimports` |
| `goimports` local-prefixes | `github.com/celestial-observability/mycli-XXXX` |
| linters | `standard` + 追加有効化（下記） |

追加で有効化する linter:
`errorlint` / `fatcontext` / `gocritic` / `gosec` / `misspell` / `modernize` / `nolintlint` / `perfsprint` / `revive` / `unconvert` / `unparam` / `usestdlibvars`

### シェルスクリプト（shellcheck + shfmt）

`scripts/e2e.sh` を `shellcheck` で検証し `shfmt` でフォーマットする。

### Makefile のターゲット構成

| ターゲット | 内容 |
|---|---|
| `fmt` | `golangci-lint fmt` + `make sh.fmt` でフォーマットする |
| `sh.fmt` | `shfmt -i 2 -w scripts/` でシェルスクリプトをフォーマットする |
| `lint` | `golangci-lint run` + `make sh.lint` を実行する |
| `sh.lint` | `shellcheck scripts/e2e.sh` を実行する |
| `build` | `go build -o mycli ./cmd/mycli` |
| `test` | `go test ./...` |
| `e2e` | `make build && bash scripts/e2e.sh` |
| `up` | `docker compose up -d`（Jaeger 起動） |
| `down` | `docker compose down`（Jaeger 停止） |
| `open` | `open http://localhost:16686`（Jaeger UI をブラウザで開く） |
| `clean` | `rm -f mycli` |
| `help` | Makefile のターゲット一覧を表示する |

## 依存関係の自動更新（Renovate）

`renovate.json5` で管理する。対象マネージャーは `docker-compose`・`github-actions`・`mise`。
クールダウンは 7 日（`minimumReleaseAge: "7 days"`）。

## CI/CD 方針

- GitHub Actions で lint・test・e2e を自動実行
- CI では `MISE_YES=1`（インタラクティブ確認をスキップ）・`MISE_ENV=ci`（`mise.ci.toml` を読み込む）を設定する
- goreleaser でバイナリリリース（GitHub Releases）
- goreleaser の archives に `LICENSE` を含める
- リリース対象: `darwin/amd64`, `darwin/arm64`
