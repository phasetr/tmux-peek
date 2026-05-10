# tmux-peek 要求整理(ドラフト)

作成日時: 2026-05-09
改訂日時: 2026-05-10

## 0. メタ情報

- **本ドキュメントの位置付け**: enkan-repl とは独立した新規 Emacs Lisp ライブラリ `tmux-peek` の要求整理. このリポジトリ `phasetr/tmux-peek` で実装する. enkan-repl 側からは将来的に optional dependency として利用しうる
- **派生関係**: 上位ドキュメントなし. 本ドキュメントが起点
- **性格**: 個人用ツールとして開始する要求メモ. まだ確定仕様ではない. 一般配布向けの互換性・抽象化より, 自分の Emacs/tmux 環境で確実に使える薄い tmux ラッパーを優先する
- **詳細化方針**: 返り値, 型変換, parser 詳細, public API の細部は実装計画ごとに段階的に詳細化する. 最初から網羅的に決めず, 必要最低限だけを決めて実装し, 実装中に判明した事実を反映する
- **関連プロジェクト**: [enkan-repl](https://github.com/phasetr/enkan-repl)

## 1. 目的・スコープ

### 1.1 目的

tmux CLI を Emacs Lisp から扱いやすくする薄いラッパーライブラリを提供する.
tmux のコマンド体系を細かく覚えていなくても, Emacs Lisp の関数としてセッション・ウィンドウ・ペイン・バッファを確認し,
状態確認と, 余計な session の削除を行えるようにする.

現状で最も欲しいのは enkan-repl で連携している tmux セッションを Emacs から簡単に確認できる方法である.
立てただけで動かしていないものや異常に増えたものを確認し, 必要に応じて tmux の session だけを kill する機能も要件に含める.
動いているものの状況・リストと, `tail` 的に末尾付近を単発で確認できるコマンドも欲しい.

tmux 上での実行や REPL 連携に関わる部分は enkan-repl 側で対応できる.
そのため tmux-peek は tmux の状態を調べる API を主軸にし, 実行系・UI 操作系は必要になった場合だけ薄い wrapper として追加する.
特に tmux の interactive UI を Emacs から操作するための機能は原則として非対応, または極めて低優先度とする.

enkan-repl は tmux を default terminal backend とし, セッション作成, テキスト送信, mirror buffer 更新, attach, kill などの
実行・運用に関わる機能をすでに持つ.
tmux-peek はその実行系を置き換えるためのものではなく, tmux の live state を取得・構造化する薄い共通部品として設計する.

ここでいう `tail` 的な確認は継続監視・購読・ストリーミング UI ではなく,
`capture-pane` 等を使って対象ペインの末尾 N 行を一度だけ取得する操作を指す.

### 1.2 スコープ

| | 取扱 |
|---|---|
| tmux CLI の薄い Emacs Lisp ラッパー | ◯ スコープ内 |
| 非同期呼び出しを基本とする API | ◯ スコープ内 |
| 複数 tmux コマンドの並列実行補助 | ◯ スコープ内 |
| 実行パス・ソケット指定のカスタマイズ | ◯ スコープ内 |
| パース結果の構造化(plist 等)した返り値提供 | ◯ スコープ内 |
| tmux の状態確認系サブコマンド(`list-*`, `display-message -p`, `capture-pane`, `show-options` 等) | ◯ 初期実装の中心 |
| tmux への操作系(`send-keys`, `split-window` 等) | ✕ 現状計画外. enkan-repl で対応できる範囲は作らない |
| 余計な session を削除する `kill-session` | ◯ スコープ内. enkan-repl の session-level lifecycle と合わせる |
| `kill-pane`, `kill-window`, `kill-server` | ✕ 現状計画外. 実装しない |
| 同期呼び出し API | ✕ 現段階では非実装. callback を受けられない呼び出し元が明確になった場合だけ再検討 |
| Emacs ウィンドウと tmux ペインのナビゲーション統合 | ✕ 範囲外. emacs-tmux-pane が担当 |
| tmux interactive UI 操作(`choose-*`, `display-menu`, `display-popup`, `command-prompt` 等) | ✕ 原則非対応. 対応する場合も極めて低優先度 |
| Emacs 側の session 一覧 UI | ◯ スコープ内. session 確認と明示削除のために実装 |
| その他の Emacs 側 UI(transient メニュー等) | △ 後続課題. コア API とは分離 |
| 特定アプリケーション(enkan-repl 等)固有のロジック | ✕ 範囲外 |

### 1.3 既存ライブラリとの位置付け

| 既存 | 性格 | tmux-peek との関係 |
| --- | --- | --- |
| emamux | 操作系(send/run/split) | 参考対象. tmux-peek は個人用途に合わせた薄い wrapper API を作る |
| turnip.el | tmux への送信系 | 補完関係 |
| emacs-tmux-pane | Emacs⇔tmux ペインのナビ統合 | 用途が異なる |
| ob-tmux | org-babel から tmux 評価 | 用途が異なる |

命名 `peek` は主な利用動機が「tmux 状況を素早く覗く」ことに由来する.
ただしライブラリ全体を read-only に限定する意味ではない.

## 2. 動作要件

### 2.1 サポート対象

- **Emacs**: 30.1 をメインサポート. 30.2 は動作するが厳密にはサポート外として扱う. それ以下のバージョンはサポートしない
- **tmux**: 3.6a をメインサポート. それ以下はサポートしない
- **OS**: macOS をメインサポート(開発環境). Linux は派生的に動作するはず(積極保証はしない)
- **依存パッケージ**: 標準同梱の `cl-lib`, `subr-x` のみ. 外部パッケージ非依存
- **配布方針**: 個人用を主目的とし, 広範な後方互換性は目的にしない

### 2.2 非機能要件

- **薄さ**: tmux CLI 呼び出しを Emacs Lisp から扱いやすく包む. tmux の意味論を過度に再実装しない
- **命名の安定性**: tmux のコマンド体系・命名にはある程度まで追随するが, ラッパーとしての安定性を重視する. public API は tmux 内部の細かな表現差よりも, 一般的な意味として分かりやすいコマンド命名体系を優先する
- **最小実装**: 必要最低限以外は作らない. 便利そうな関数, 網羅的な wrapper, UI, 汎用化は要求が明確になるまで追加しない
- **非同期優先**: 基本経路は `make-process` ベースの非同期実行にする. 同期 API は主経路にしない
- **責務分離**: enkan-repl で対応できる実行・送信・接続系は tmux-peek では作らない. tmux-peek は状態確認・情報取得を優先する. ただし enkan-repl で作られた余計な session を確認して削除するための `kill-session` は明確に対象に含める
- **リファクタリング要求**: 実装を急いで積み上げたままにしない. executor, parser, public API の境界が見えた段階, および機能追加前の節目で徹底的にリファクタリングし, 小さい安定した構成に戻す
- **テスタビリティ**: tmux 呼び出し部とパース部を分離し, パース部は純粋関数として ERT で網羅可能にする
- **エラー区別可能性**: tmux 不在 / サーバー不在 / ターゲット不在 / 一般失敗 を呼び出し側で識別できる

## 3. 機能要件

### 3.1 一覧取得系

| tmux サブコマンド | elisp 関数(非同期) | 返り値の大枠 |
|---|---|---|
| `list-sessions` | `tmux-peek-list-sessions-async` | session の構造化リスト |
| `list-windows` | `tmux-peek-list-windows-async` | window の構造化リスト |
| `list-panes` | `tmux-peek-list-panes-async` | pane の構造化リスト |
| `list-clients` | `tmux-peek-list-clients-async` | client の構造化リスト |
| `list-buffers` | `tmux-peek-list-buffers-async` | paste-buffer の構造化リスト |

### 3.2 内容取得系

| tmux サブコマンド | elisp 関数 | 用途 |
|---|---|---|
| `capture-pane -p` | `tmux-peek-capture-pane-async` | ペインの可視内容またはスクロールバックを文字列で取得. `:tail-lines` は単発末尾取得 |
| `show-buffer` | `tmux-peek-show-buffer-async` | 指定ペーストバッファの内容文字列 |

### 3.3 メタ情報取得系

| tmux サブコマンド | elisp 関数 | 用途 |
|---|---|---|
| `display-message -p '<format>'` | `tmux-peek-display-message-async` | 任意フォーマット文字列を tmux で展開した結果を取得. 全メタ情報取得の最低レイヤ |
| `show-options` | `tmux-peek-show-options-async` | global / session / window のオプション照会 |
| `show-environment` | `tmux-peek-show-environment-async` | 環境変数照会 |

### 3.4 削除系

enkan-repl で異常に作られた, または enkan-repl 側だけでは kill しきれない可能性がある tmux 対象を確認し,
余計な session を削除するため, `kill-session` だけを明確にスコープ内とする.
現状の enkan-repl は pane ではなく session 単位で tmux を立ち上げ・削除するため, cleanup も session-level に合わせる.
削除系は状態確認 API と組み合わせて使うことを前提にし, 自動判断による削除は行わない.

| tmux サブコマンド | elisp 関数 | 用途 |
|---|---|---|
| `kill-session` | `tmux-peek-kill-session-async` | 指定セッション削除 |

`kill-pane`, `kill-window`, `kill-server` は実装しない.
必要になった場合もこの要求整理を明示的に改訂するまでは追加しない.

### 3.5 非対応・現状計画外

tmux 上での実行や REPL 連携は enkan-repl 側で対応できるため, tmux-peek の現状計画からは外す.
以下は将来必要が明確にならない限り実装しない.

| tmux サブコマンド群 | 取扱 |
|---|---|
| `new-session`, `new-window`, `split-window`, `respawn-*` 等の起動・構成系 | 現状計画外 |
| `send-keys`, `paste-buffer` 等の入力・送信系 | 現状計画外. enkan-repl 側で対応 |
| `attach-session`, `detach-client`, `switch-client` 等の接続系 | 現状計画外 |
| `kill-pane`, `kill-window`, `kill-server` | 現状計画外 |
| `choose-*`, `display-menu`, `display-popup`, `command-prompt` 等の tmux interactive UI 系 | 原則非対応 |

tmux-peek は状態確認・情報取得のための薄い wrapper として設計し,
実行・送信・接続・UI 制御の責務は持たない. `kill-session` は余計な session の掃除用途として例外的に扱う.

### 3.6 補助関数

- `tmux-peek-server-running-p-async`: tmux サーバーが起動しているかを真偽値で返す
- `tmux-peek-version-async`: tmux 自身のバージョン文字列を返す
- `tmux-peek-target-exists-p-async`: 指定ターゲット(`session`, `session:window`, `session:window.pane`)の存在確認

### 3.7 セッション一覧 UI

- `tmux-peek-session-list`: Emacs の専用バッファで tmux session 一覧を表示する
- 一覧バッファでは refresh, quit, session 削除を行える
- session 削除は `tmux-peek-kill-session-async` を使い, 対象 session をユーザーが明示的に選ぶ
- 自動判定による削除は行わない

## 4. API 設計方針

### 4.1 命名規約

- 全関数は `tmux-peek-` プレフィクス
- 内部関数は `tmux-peek--` ダブルハイフン
- 非同期版はサフィックス `-async` を付ける. 初期実装では非同期版を基本形とする
- 同期版は現段階では追加しない. 必要性が明確になった場合だけ, 非同期 executor の薄い wrapper として再検討する

### 4.2 非同期版 API シグネチャ

```elisp
(tmux-peek-list-sessions-async callback &optional opts)
;; callback は 1 引数: result plist
;;   成功: (:ok t :value <データ> :stdout "..." :stderr "" :exit-code 0)
;;   失敗: (:ok nil :error <エラーシンボル> :exit-code N :stderr "...")
```

- 戻り値は `tmux-peek-process` 構造体または plist handle とする
- handle は process object, timer, stdout/stderr buffer, 完了状態を保持する
- callback は Emacs のプロセス sentinel/filter 経由で呼ばれる
- 非同期 callback 内では `signal` せず, result plist で成功/失敗を返す

### 4.3 同期版 API の扱い

同期版は現段階では実装しない.
必要になる理由は callback を受けられない既存呼び出し元との互換性に限る.
追加する場合も非同期 executor を使う薄い wrapper にし, 別経路の tmux 実行実装は作らない.
`accept-process-output` によるブロック・再入性リスクを避けるため, 主経路にはしない.

### 4.4 オプション引数 `opts`

plist で受け取り, 以下を共通サポート:

| キー | 型 | 説明 |
|---|---|---|
| `:target` | string | `-t` に渡すターゲット指定 |
| `:socket-name` | string | `-L` に渡すソケット名 |
| `:socket-path` | string | `-S` に渡すソケットパス |
| `:tmux-executable` | string | tmux 実行パス. 既定はカスタム変数値 |
| `:timeout` | number | 非同期版でのタイムアウト秒数 |

サブコマンド固有のオプションは個別関数のシグネチャで追加.

### 4.5 カスタム変数

- `tmux-peek-tmux-executable`: 既定 `"tmux"`
- `tmux-peek-default-socket-name`: 既定 `nil`
- `tmux-peek-default-session-fields`: list-sessions のフォーマットフィールド既定セット
- `tmux-peek-default-window-fields`: 同上(window)
- `tmux-peek-default-pane-fields`: 同上(pane)
- `tmux-peek-default-client-fields`: 同上(client)
- `tmux-peek-default-buffer-fields`: 同上(buffer)
- `tmux-peek-default-timeout`: 非同期版の既定タイムアウト

### 4.6 返り値の構造

返り値の詳細は現時点では確定仕様にしない.
実装計画を進めながら, 各段階で必要な最小形だけを決める.

現時点の大まかな要求は以下に留める.

- 一覧系は構造化されたコレクションとして返す
- `capture-pane` / `show-buffer` は文字列を返す
- `display-message` は tmux format 展開後の文字列を返す
- `kill-session` は成功/失敗を非同期 result として返す
- 詳細な plist key, 型変換, default fields は parser 実装時に決める

### 4.7 tmux 出力フォーマット

`list-*` 系は tmux の `-F` を使う.
初期実装では tmux 3.6a の統合テストでそのまま扱えた printable delimiter `|||` をフィールド区切りに使う.
必要な一覧系だけで成立する最小方式として採用し, 問題が見えた段階でリファクタリングする.

### 4.8 `tail` 的取得

`tmux-peek-capture-pane-async` は `:tail-lines N` を受け付ける.
これは対象ペインの末尾 N 行を一度だけ取得する単発操作であり, 継続監視ではない.
`watch`, polling, streaming は別機能として扱う.

## 5. 非同期性の設計

### 5.1 内部実装

- **コア層**(`tmux-peek--exec-async`): `make-process` ベース. stdout/stderr を蓄積し, sentinel で完了通知. これを唯一の tmux 呼び出し経路とする
- **handle 層**: process object, timer, callback, buffers, 完了フラグをまとめる
- **同期層**: 現段階では作らない. 必要になった場合だけ非同期 executor の補助 wrapper として追加する

非同期経路を本体とし, 同期版は設計・テストの優先度を下げる.

### 5.2 並列実行のサポート

- `tmux-peek-parallel-async`: 複数の tmux-peek 非同期呼び出しをまとめて実行し, 全完了で集約 callback を呼ぶ補助関数を提供
- 呼び出し例: list-sessions と list-windows を同時に取って統合ビューを構築
- 並列実行は初期実装対象とする

### 5.3 キャンセル・タイムアウト

- 全非同期関数は戻り値として handle を返す
- `tmux-peek-cancel`: handle 内のプロセスを SIGTERM で中断し, timer/buffer を片付ける
- `:timeout` 経過で自動的に SIGTERM 後 `(:ok nil :error 'tmux-peek-error-timeout)` を返す

### 5.4 将来拡張のための余地

- **キャッシュ層**: 一覧系は短時間で連続呼び出されうる. TTL 付きメモ化を opt-in で挟めるよう, コア層の手前にデコレータ層を入れられる構造で実装
- **購読/監視**: tmux の `hook` 機構と組み合わせる `tmux-peek-watch-*` は将来拡張として扱う
- **ストリーミング**: `capture-pane` の継続取得など, sentinel ではなく filter で逐次処理する系統を将来追加できるよう, コア層に filter 注入点を残す

## 6. エラー設計

### 6.1 エラーシンボル階層

```
tmux-peek-error                   ;; 親
├── tmux-peek-error-not-found     ;; tmux 実行ファイル不在
├── tmux-peek-error-no-server     ;; tmux サーバー未起動
├── tmux-peek-error-no-target     ;; 指定ターゲット不在
├── tmux-peek-error-timeout       ;; 非同期タイムアウト
├── tmux-peek-error-parse         ;; 出力パース失敗
└── tmux-peek-error-exec          ;; 上記以外の exit code 非ゼロ
```

`define-error` で親子関係を定義し, 呼び出し側は粒度を選んで `condition-case` できる.

### 6.2 エラー識別の判定基準

- **not-found**: `executable-find` 失敗 / `make-process` の ENOENT
- **no-server**: stderr に `no server running` を含む
- **no-target**: stderr に `can't find session|window|pane` 系
- **parse**: stdout は得たが既知フォーマットに合致しない
- **exec**: 上記いずれにも該当しない exit code 非ゼロ

tmux プロセスには可能な限り `LC_ALL=C` を渡し, stderr 判定を英語メッセージ前提に寄せる.

### 6.3 同期/非同期での扱い

- 非同期版: 上記 6.1 のシンボルを `:error` キーに格納した plist を callback 引数として渡す(`signal` しない)
- 同期版: 現段階では非実装. 追加する場合は非同期 result を `signal` に変換する薄い wrapper に限定する

## 7. テスト戦略

### 7.1 純粋関数層(必須・カバレッジ重視)

- フォーマット指定生成関数 `tmux-peek--format-spec` (フィールド plist → `-F` 引数文字列)
- パーサ群 `tmux-peek--parse-list-*` (区切り済 stdout → plist のリスト)
- エラー分類器 `tmux-peek--classify-stderr` (stderr → エラーシンボル)
- 引数組み立て関数 `tmux-peek--build-args`

これらは ERT で入力出力を直接突き合わせる. tmux は呼ばない.

### 7.2 統合テスト(オプション)

- 専用ソケット名で tmux サーバーを起動 → 各 API 呼び出し → 結果検証 → サーバー終了
- CI では tmux インストール環境が必要なため Make ターゲットを分離(`make test-integration`)

### 7.3 非同期 callback のテスト

- ERT で `accept-process-output` を回しつつ完了を待つヘルパを用意
- タイムアウトテストは短い `:timeout` を指定して挙動確認

## 8. ファイル構成(このリポジトリ)

```
tmux-peek/
├── tmux-peek.el                  ;; entry point / public require
├── tmux-peek-async.el            ;; make-process executor, handle, parallel
├── tmux-peek-command.el          ;; tmux 引数組み立て
├── tmux-peek-parse.el            ;; list/show/capture parser
├── tmux-peek-error.el            ;; define-error, stderr classifier
├── tmux-peek-api.el              ;; public API
├── tmux-peek-session-list.el     ;; tabulated session list UI
├── README.org
├── Makefile
├── test/
│   ├── tmux-peek-command-test.el
│   ├── tmux-peek-parser-test.el
│   ├── tmux-peek-error-test.el
│   ├── tmux-peek-async-test.el
│   └── tmux-peek-integration-test.el  ;; 実 tmux 必要
```

分割構成を基本とし, `tmux-peek.el` は主要ファイルを `require` する entry point に留める.

## 9. enkan-repl からの利用方針(参考)

- 対象リポジトリ: <https://github.com/phasetr/enkan-repl>
- 直接依存はしない. ユーザー環境に tmux-peek が存在すれば連携機能が有効化される `(when (require 'tmux-peek nil t) ...)` 方式
- enkan-repl 側からは主に以下を利用する想定:
  - `tmux-peek-server-running-p-async` で tmux 利用可否確認
  - `tmux-peek-list-panes-async` でアクティブペイン把握
  - `tmux-peek-display-message-async` で `#{pane_pid}` 等の取得
  - `tmux-peek-capture-pane-async` / `:tail-lines` で AI CLI 出力の末尾確認
  - enkan-repl だけでは kill しきれない可能性がある余計な session の確認と `kill-session`

これらは tmux-peek の汎用 API として提供されるので, enkan-repl 固有のヘルパーは enkan-repl 側に薄く置く.
enkan-repl の tmux backend には `send-keys`, `new-session`, `new-window`, `kill-window`, `kill-session`,
mirror buffer 用の `capture-pane`, 外部 terminal attach などが既にある.
tmux-peek 側では状態確認 API の安定化を優先しつつ, enkan-repl で作られた余計な session を掃除するための `kill-session` だけは実装対象に含める.
`kill-pane`, `kill-window`, `kill-server` は tmux-peek では実装しない.

## 10. 確定事項(プロジェクト立ち上げ条件)

- **ライセンス**: GPL-3.0-or-later. Emacs エコシステム慣例に沿い, Emacs 本体および既存 tmux 連携パッケージ群との互換性を確保する
- **MELPA 申請**: 行わない
- **README**: 英語(`README.org` または `README.md`. 形式は実装プロジェクト立ち上げ時に決定)
- **リポジトリ**: `phasetr/tmux-peek`

ファイル冒頭の `;;; tmux-peek.el --- ...` ヘッダおよび各ソースファイルにはGPL-3.0+ の標準ライセンスヘッダを付与する.

## 11. 初期実装計画

### 11.1 第一段階: 土台

- 分割ファイル構成を作る
- GPL-3.0-or-later のヘッダ, `provide` / `require` の依存関係を整える
- Makefile に byte-compile, checkdoc, ERT のターゲットを作る
- この段階では詳細 API を作り込みすぎない

### 11.2 第二段階: 非同期 executor

- `tmux-peek--exec-async` を実装する
- handle, timeout, cancel, stdout/stderr 蓄積, error result を実装する
- `tmux-peek-parallel-async` を実装する
- ERT では tmux に依存しないダミープロセスまたは軽量コマンドで非同期 callback を検証する
- 完了後に executor / handle / callback 周辺を徹底的にリファクタリングする

### 11.3 第三段階: コマンド構築と parser

- socket/executable/target/options を反映する `tmux-peek--build-args` を実装する
- `list-*` 用の field definition と `-F` 生成を実装する
- 必要な最小 parser と型変換を実装する
- stderr classifier を実装する
- 返り値の plist key, 型変換, default fields はこの段階で実装に合わせて詳細化する
- 完了後に command builder / parser / error classifier の境界を徹底的にリファクタリングする

### 11.4 第四段階: public API

- `list-sessions-async`, `list-windows-async`, `list-panes-async`, `list-clients-async`, `list-buffers-async`
- `display-message-async`, `capture-pane-async`, `show-buffer-async`
- `capture-pane-async` の `:tail-lines` 単発末尾取得
- `server-running-p-async`, `version-async`, `target-exists-p-async`
- `session-list` UI
- 必要最低限の API だけを作り, 便利 API は要求が明確になるまで作らない
- public API を広げる前に命名と引数構造を見直す

### 11.5 第五段階: session 削除系

- `kill-session-async`
- 削除前に `target-exists-p-async` と組み合わせられる API 形にする
- 自動判定で kill する関数は作らず, 呼び出し側が明示した session target だけを削除する
- `kill-pane`, `kill-window`, `kill-server` は実装しない. 誤用防止のため API として存在させない

### 11.6 第六段階: enkan-repl 連携前提の確認

- enkan-repl の tmux backend が必要とする状態確認 API を棚卸しする
- `list-panes`, `display-message`, `capture-pane`, `server-running-p`, `target-exists-p`, `kill-session` の不足を確認する
- enkan-repl 側で既に対応できる start/send/attach/mirror 運用系は tmux-peek では実装しない
- tmux interactive UI 系は実装しない

### 11.7 第七段階: 統合確認とリファクタリング

- 専用 socket name を使う integration test を追加する
- 実 tmux 3.6a で list/display/capture/show/kill-session 系の動作を確認する
- README に個人用前提, 対応環境, 非同期優先 API, `tail` 的取得の意味を書く
- 統合確認後, 追加機能を入れる前に全体を徹底的にリファクタリングする
- 不要な wrapper, 重すぎる抽象, 使わないオプションは削る
