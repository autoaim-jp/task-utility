#!/bin/bash

update-gitlab-mr-body() {
    local iid="$1"
    # フロー: 引数検証
    [[ -z "$iid" ]] && { echo "Usage: update-gitlab-mr-body <merge_request_iid>" >&2; return 1; }

    # フロー: Git ルート取得
    local root
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    # フロー: ローカル Markdown ファイル存在確認
    local file="$root/__download/mr_${iid}.md"
    [[ -f "$file" ]] || { echo "✗ $file がありません"; return 1; }

    # フロー: GITLAB_TOKEN 確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    # フロー: GitLab API で MR 本文を更新 (.md 全文)
    curl -sfS -X PUT \
      -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
      --data "$(jq -Rs '{description: .}' < "$file")" \
      "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/merge_requests/$iid" \
      >/dev/null 2>&1 \
      || { echo "✗ API 失敗"; return 1; }

    # フロー: ローカル Markdown ファイル削除
    rm -f "$file"

    # フロー: Cursor で開いているタブを閉じる
    cursor_window=$(xdotool search --name "Cursor" | head -1)
    if [ -n "$cursor_window" ]; then
        xdotool windowactivate "$cursor_window" >/dev/null 2>&1
        sleep 0.2
        xdotool key ctrl+1 >/dev/null 2>&1
        sleep 0.2
        xdotool key ctrl+w >/dev/null 2>&1
        sleep 0.3
    fi

    # フロー: ブラウザで MR を開く
    nohup xdg-open "$GITLAB_HOST/$GITLAB_PROJ_RAW/-/merge_requests/$iid" >/dev/null 2>&1 &
    disown

    echo "✓ Updated and cleaned up MR \!$iid"
}
