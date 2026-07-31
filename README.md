# claude-code-statusline

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI のカスタムステータスラインです。セッション情報をひと目で確認できます。

## プレビュー

```
🔀 ~/source/my-project on 🌿 feature/auth
🤖 Claude Opus 5 | ⚡ high | 📊 43.3K | 🧠 [####------] 40.0% | 🔄 60.0%
⏱️  5h [█░░░░░░░]  12% · 7d [██░░░░░░]  23% (100h)
```

## 機能

- **カレントディレクトリ** - ホームを `~` に置換し、深い階層は `~/.../<親>/<末尾>` に短縮
- **Gitブランチ** - Gitリポジトリ内ではブランチ名を表示
- **モデル名** - 使用中のClaudeモデルを表示
- **Effortレベル** - リーズニングEffort（`low`/`medium`/`high`/`xhigh`/`max`）を表示。対応モデルのみ
- **使用トークン数** - コンテキストに載っているトークン数（例: `43.3K`）
- **コンテキスト使用率** - Auto-Compact閾値を基準に正規化した使用率を色付きプログレスバー（10マス、1マス=10%）で表示
- **コンテキスト残量** - 残りコンテキストの割合を表示
- **5時間 / 週次の使用量上限** - Claude.aiサブスクの利用枠の消費率を箱型メーターで表示（3行目）
- **色分け**:
  - 🟢 緑: 50%未満
  - 🟡 黄: 50-79%
  - 🔴 赤: 80%以上

### 使用量上限の表示（3行目）

Claude.aiサブスク利用時、最初のAPI応答以降に `rate_limits` が渡されると3行目が表示されます。取得できない場合（API未応答、APIキー利用時など）は3行目ごと省略されます。

```
⏱️  5h [█░░░░░░░]  12% · 7d [██░░░░░░]  23% (100h)
```

- `5h` - 5時間セッション枠の消費率（8分割の箱型メーター、1マス=12.5%。1%以上なら最低1マス点灯）
- `7d` - 週次（7日）枠の消費率
- `(100h)` - 週次枠がリセットされるまでの残り時間（時間単位）。5時間枠のリセットは自明なため表示しません

メーターの幅は環境変数 `CLAUDE_RATE_METER_WIDTH` で変更できます（既定8マス）。
コンテキストバーの幅は `CLAUDE_CTX_BAR_WIDTH` で変更できます（既定10マス）。

### Auto-Compact閾値の正規化

Claude Codeの `used_percentage` と `remaining_percentage` の合計は Auto-Compact の閾値（通常95%）になります。本ステータスラインでは、この閾値を100%として正規化して表示します。

例: `used=47.5%`, `remaining=47.5%`（閾値95%）→ 使用率 `50.0%` / 残量 `50.0%` と表示

## 前提条件

- **Bash**（macOS/Linux標準、Windowsでは [Git for Windows](https://gitforwindows.org/) のGit Bashで利用可能）
- **awk** - パーセンテージ計算に使用（通常プリインストール済み）
- **git** - ブランチ表示に使用（オプション）
- **jq** - インストールスクリプト (`install.sh`) で使用

> **Note**: `statusline.sh` 本体は jq に依存せず、sed/grep で JSON をパースします。

## インストール

### クイックインストール

```bash
git clone https://github.com/ueki-interpark/claude-code-statusline.git
cd claude-code-statusline
./install.sh
```

インストールスクリプトは以下を行います:
1. `statusline.sh` を `~/.claude/` にコピー
2. `~/.claude/settings.json` に statusLine 設定を追加
3. 既存の settings.json をバックアップ

### 手動インストール

1. `statusline.sh` を `~/.claude/` にコピー:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. `~/.claude/settings.json` に以下を追加:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

3. Claude Code を再起動してください。

## カスタマイズ

`~/.claude/statusline.sh` を編集してカスタマイズできます。スクリプトは標準入力からClaude Codeが提供するJSONを受け取ります。

### 使用しているフィールド

| フィールド | 型 | 説明 |
|-------|------|-------------|
| `model.display_name` | string | 使用中のモデル名（例: "Claude Opus 5"） |
| `cwd` | string | カレントディレクトリ |
| `effort.level` | string | リーズニングEffort。対応モデルでのみ渡される |
| `context_window.context_window_size` | number | モデルのコンテキストウィンドウサイズ |
| `context_window.current_usage.*` | number | `input_tokens` / `output_tokens` / `cache_creation_input_tokens` / `cache_read_input_tokens` |
| `rate_limits.five_hour.used_percentage` | number | 5時間枠の消費率（0-100） |
| `rate_limits.five_hour.resets_at` | number | 5時間枠のリセット時刻（Unix epoch秒） |
| `rate_limits.seven_day.used_percentage` | number | 週次枠の消費率（0-100） |
| `rate_limits.seven_day.resets_at` | number | 週次枠のリセット時刻（Unix epoch秒） |

### カスタマイズ例

**プログレスバーのスタイル変更:**

```bash
# ブロック文字を使用（tr はマルチバイト文字で失敗することがあるため repeat_char を使う）
BAR=$(repeat_char "$FILLED" '█')$(repeat_char "$EMPTY" '░')
```

**警告しきい値の変更:**

```bash
# コンテキスト警告を60%に変更（正規化後の値で判定）
if [ "$ADJUSTED_USED_INT" -ge 60 ]; then
  CTX_COLOR="$RED"
fi
```

**アイコンの削除（絵文字非対応ターミナル向け）:**

```bash
LINE1="${CYAN}${SHORT_DIR}${RESET} ${DIM}on${RESET} ${MAGENTA}${BRANCH}${RESET}"
```

## ライセンス

[MIT](LICENSE)
