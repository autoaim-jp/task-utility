#!/bin/bash

get-gitlab-mr-body() {
    local iid="$1"
    # フロー: 引数検証
    [[ -z "$iid" ]] && { echo "Usage: get-gitlab-mr-body <merge_request_iid>" >&2; return 1; }

    # フロー: Git ルート取得
    local root
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    local dir="$root/__download"
    local file="$dir/mr_${iid}.md"
    mkdir -p "$dir"

    # フロー: GITLAB_TOKEN 確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    # フロー: 既存ファイルチェック
    [[ -f "$file" ]] && { echo "✗ $file が既に存在しています。上書きできません。"; return 1; }

    # フロー: GitLab API から MR 本文取得 (Markdown 化)
    local mr=$(curl -sfS -H "PRIVATE-TOKEN:$GITLAB_TOKEN" \
        "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/merge_requests/$iid") || return 1

    jq -r '.description' <<<"$mr" >"$file"

    # フロー: Cursor で Markdown を開く
    cursor --reuse-window "$file" >/dev/null 2>&1 &
    disown
}
