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
    # #259 更新: mr-###-タイトル.md
    local file_pattern="$dir/mr-${iid}-.+\.md"
    local file_count=$(find "$dir" -type f -regex "$file_pattern" | wc -l)

    mkdir -p "$dir"

    # フロー: GITLAB_TOKEN 確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    # フロー: 既存ファイルチェック
    if [[ "$file_count" -ne 0 ]]; then
        echo "✗ mr-${iid}-から始まるファイルが既に存在しています。上書きできません。"; return 1;
    fi

    # フロー: GitLab API から MR 本文取得 (Markdown 化)
    local mr=$(curl -sfS -H "PRIVATE-TOKEN:$GITLAB_TOKEN" \
        "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/merge_requests/$iid") || return 1

    local title=$(jq -r '.title' <<<"$mr")
    local title_sanitized=$(printf '%s' "$title" \
             | sed -e 's/[\/\\:*?"<>|. ]/_/g' \
                   -e 's/[[:cntrl:]]/_/g' \
                   | cut -c-100)
    local file="$dir/mr-${iid}-${title_sanitized}.md"

    jq -r '.description' <<<"$mr" >"$file"

    # フロー: Cursor で Markdown を開く
    cursor --reuse-window "$file" >/dev/null 2>&1 &
    disown
}
