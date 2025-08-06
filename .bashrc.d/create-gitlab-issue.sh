#!/bin/bash

create-gitlab-issue() {
    local file_id="$1"
    # フロー: 引数検証
    [[ -z "$file_id" ]] && { echo "Usage: create-gitlab-issue <file_id>" >&2; return 1; }

    local root
    # フロー: Git ルート取得
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    # フロー: GITLAB_TOKEN など環境変数確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    local dir="$root/__download"
    # #259 更新: issue-###-タイトル.md
    local file_pattern="$dir/issue-${file_id}-.+\.md"
    local file_count=$(find "$dir" -type f -regex "$file_pattern" | wc -l)

    # フロー: Markdown ファイル存在確認
    if [[ "$file_count" -eq 0 ]]; then
        echo "✗ issue-${file_id}-から始まるファイルがありません"; return 1;
    elif [[ "$file_count" -ne 1 ]]; then
        echo "✗ issue-${file_id}-から始まるファイルを一つにしてください"; return 1;
    fi

    local file=$(find "$dir" -type f -regex "$file_pattern" | head -n 1)
    
    local title
    # フロー: 1 行目からタイトル抽出 (`# タイトル #issue番号`)
    # 1行目の`# `から最後の`#`の手前まで出す。
    title="$(sed -n '1p' "$file" | sed -n 's/^# \(.*\) #[^#]*$/\1/p')"
    [[ -z "$title" ]] && { echo "✗ タイトルが空です"; return 1; }

    local description
    # フロー: Markdown 全文読み込み
    description="$(cat "$file")"
    [[ -z "$description" ]] && { echo "✗ 本文が空です"; return 1; }

    # フロー: GitLab API: POST /issues
    response=$(curl -sfS -X POST \
    -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
    --data "$(jq -Rn --arg t "$title" --arg d "$description" '{title:$t,description:$d}')" \
    "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues") \
    || { echo "✗ API 失敗"; return 1; }

    # フロー: iid 抽出
    iid=$(echo "$response" | jq -r '.iid')
    [[ -z "$iid" || "$iid" == "null" ]] && { echo "✗ issue番号の取得に失敗しました"; return 1; }

    echo "✓ issue #${iid} を作成しました。"

    # フロー: Markdown の 1 行目を iid で置換
    description="$(sed '1s/#[^#]*$/#'"${iid}"'/' <<< "$description")"

    # フロー: GitLab API: PUT /issues/{iid}
    curl -sfS -X PUT \
    -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
    --data "$(jq -Rn --arg d "$description" '{description:$d}')" \
    "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid" \
    >/dev/null 2>&1 \
    || { echo "✗ API 失敗"; return 1; }
    echo "✓ issue #${iid} の1行目のissue番号を更新しました。"

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

    # フロー: ブラウザで Issue を開く
    nohup xdg-open "$GITLAB_HOST/$GITLAB_PROJ_RAW/-/issues/$iid" >/dev/null 2>&1 &
    disown

    # フロー: ローカル Markdown ファイル削除
    rm -f "$file"
}
