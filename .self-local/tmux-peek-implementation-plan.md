# tmux-peek 実装計画

作成日時: 2026-05-10

## 0. 前提

- 要求整理: `.self-local/tmux-peek-requirements.md`
- この計画は確定仕様ではない. 実装しながら必要最小限を段階的に詳細化する
- 主目的は tmux の live state 確認と, 余計な pane の明示的な `kill-pane`
- enkan-repl で対応できる start/send/attach/mirror 運用系は作らない
- `kill-session`, `kill-window`, `kill-server` は危険な封印対象として実装しない
- 各段階の節目でリファクタリングする

## 1. 土台作成

- `tmux-peek.el`
- `tmux-peek-async.el`
- `tmux-peek-command.el`
- `tmux-peek-parse.el`
- `tmux-peek-error.el`
- `tmux-peek-api.el`
- `README.org`
- `Makefile`
- `test/`

やること:

- GPL-3.0-or-later のヘッダを付ける
- `provide` / `require` の依存関係を最小で整える
- `make check`, `make test`, `make compile` 相当のターゲットを作る
- この段階では API 詳細を作り込みすぎない

## 2. 非同期 executor

実装対象:

- `tmux-peek--exec-async`
- process handle
- timeout
- cancel
- stdout/stderr 蓄積
- callback result
- `tmux-peek-parallel-async`

確認事項:

- callback は `(:ok t ...)` / `(:ok nil ...)` で返す
- 非同期 callback 内では `signal` しない
- tmux に依存しない軽量コマンドで ERT できる形にする

リファクタリング:

- executor / handle / callback result の境界を見直す
- 過剰な抽象があれば削る

## 3. コマンド構築

共通 opts:

- `:tmux-executable`
- `:socket-name`
- `:socket-path`
- `:target`
- `:timeout`

実装対象:

- `tmux-peek--build-args`
- `list-*` 系の引数生成
- `display-message` の引数生成
- `capture-pane` の引数生成
- `show-*` 系の引数生成
- `kill-pane` の引数生成

作らないもの:

- `new-session`
- `new-window`
- `split-window`
- `send-keys`
- `attach-session`
- `kill-session`
- `kill-window`
- `kill-server`
- tmux interactive UI 系

## 4. Parser とエラー分類

優先 parser:

- `list-sessions`
- `list-windows`
- `list-panes`

後回し parser:

- `list-clients`
- `list-buffers`
- `show-options`
- `show-environment`

この段階で決めること:

- `list-*` の最小 default fields
- plist key
- 型変換
- tmux `-F` の区切り方式: 初期実装では printable delimiter `|||`
- parse error の扱い

エラー分類:

- tmux executable not found
- no server
- no target
- timeout
- parse error
- generic exec error

リファクタリング:

- command builder / parser / error classifier の境界を見直す
- 実装に合わせて要求整理へ反映する

## 5. Public API

優先実装:

- `tmux-peek-list-sessions-async`
- `tmux-peek-list-windows-async`
- `tmux-peek-list-panes-async`
- `tmux-peek-display-message-async`
- `tmux-peek-capture-pane-async`
- `tmux-peek-target-exists-p-async`
- `tmux-peek-server-running-p-async`
- `tmux-peek-kill-pane-async`

後回し候補:

- `tmux-peek-list-clients-async`
- `tmux-peek-list-buffers-async`
- `tmux-peek-show-buffer-async`
- `tmux-peek-show-options-async`
- `tmux-peek-show-environment-async`
- 同期補助版: 現段階では作らない. callback を受けられない呼び出し元が明確になった場合だけ検討する

方針:

- 必要最低限だけ作る
- 便利 API は要求が明確になるまで作らない
- public API を広げる前に命名と引数構造を見直す
- 同期補助版を作る場合も非同期 executor の薄い wrapper に限定し, 別経路の tmux 実行実装は作らない

## 6. Pane 削除

実装対象:

- `tmux-peek-kill-pane-async`

方針:

- 呼び出し側が明示した pane target だけを削除する
- 自動判定で kill する関数は作らない
- `target-exists-p-async` と組み合わせやすい形にする
- `kill-session`, `kill-window`, `kill-server` は API として存在させない

## 7. 統合確認

専用 socket name を使って確認する:

- tmux server running
- list sessions
- list windows
- list panes
- display message
- capture pane
- `:tail-lines`
- target exists
- kill pane

実 tmux 3.6a で確認する.

## 8. enkan-repl 前提確認

確認対象:

- enkan-repl の tmux backend が必要とする state 確認 API
- `list-panes`
- `display-message`
- `capture-pane`
- `server-running-p`
- `target-exists-p`
- `kill-pane`

作らないもの:

- enkan-repl 側で既に対応できる start/send/attach/mirror 運用系
- tmux interactive UI 系

## 9. README と整理

README に書くこと:

- 個人用前提
- 対応環境
- 非同期優先 API
- enkan-repl との関係
- `tail` 的取得は単発末尾取得
- `kill-pane` だけを作る
- `kill-session`, `kill-window`, `kill-server` は作らない
- 同期補助版は現段階では未実装であり, 必要な理由は callback を受けられない呼び出し元との互換性に限る

最後にやること:

- 全体を徹底的にリファクタリングする
- 不要な wrapper を削る
- 重すぎる抽象を削る
- 使わない opts を削る
- 要求整理と README を実装結果に合わせて更新する
