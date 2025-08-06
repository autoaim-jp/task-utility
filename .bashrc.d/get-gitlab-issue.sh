#!/bin/bash

get-gitlab-issue() {
    local iid="$1"
    # フロー: 引数検証
    [[ -z "$iid" ]] && { echo "Usage: get-gitlab-issue <issue_number> [is_bk_only]" >&2; return 1; }
    local is_bk_only="${2:-}"

    local root
    # フロー: Git ルート取得
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    local dir="$root/__download"
    # #259 更新: issue-###-タイトル.md
    local file_pattern="$dir/issue-${file_id}-.+\.md"
    local file_count=$(find "$dir" -type f -regex "$file_pattern" | wc -l)

    mkdir -p "$dir" "$dir/__bk/"

    # フロー: GITLAB_TOKEN など環境変数確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    # フロー: 既存ファイルチェックとバックアップモード判定
    if [[ "$is_bk_only" == "true" ]]; then
        file="${file}__tmp"
    elif [[ "$file_count" -ne 0 ]]; then
        echo "✗ $file が既に存在しています。上書きできません。"; return 1;
    fi

    # フロー: GitLab API から本文 + コメント取得 (Markdown 化)
    local issue=$(curl -sfS -H "PRIVATE-TOKEN:$GITLAB_TOKEN" \
        "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid") || return 1

    # #132 追加
    # issueが存在しない場合（$issueが空）は、異常終了
    if [[ -z "$issue" ]]; then
        echo "✗ $iid のissueがGitLab上に存在しません" >&2
        return 1
    fi

    # #259 更新: issue-###-タイトル.md
    # 日本語や記号は許可し、ファイル名として使えない文字を置換
    local title=$(jq -r '.title' <<<"$issue")
    local title_sanitized=$(printf '%s' "$title" \
             | sed -e 's/[\/\\:*?"<>|. ]/_/g' \
                   -e 's/[[:cntrl:]]/_/g' \
                   | cut -c-100)
    local file="$dir/issue-${iid}-${title_sanitized}.md"

    # フロー: ファイル生成 (バウンダリ区切り)
    local timestamp
    timestamp="$(date +"%Y%m%d%H%M%S%3N")"
    local boundary="##### -boundary-${timestamp}"

    # #259 更新: ページネーション対応
    # フロー: コメント取得
    page=1
    all_notes="[]"
    while :; do
    page_json=$(curl -sfS -H "PRIVATE-TOKEN:$GITLAB_TOKEN" \
                "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid/notes?per_page=100&page=$page")

    # 何も返ってこなければループ終了
    [[ $(jq 'length' <<<"$page_json") -eq 0 ]] && break

    # ページをマージ
    all_notes=$(jq -s 'add' <(echo "$all_notes") <(echo "$page_json"))
    ((page++))
    done

    # #204 追加: 本文更新やメンションなどは除外する
    notes=$(jq '[ .[] | select(.system | not) ]' <<<"$all_notes")
    {
      echo "$boundary"
      echo "[タイトル]"
      jq -r '.title' <<<"$issue"
      echo "$boundary"
      echo "[本文]"
      jq -r '.description' <<<"$issue"
      echo "$boundary"
      jq -r --arg b "$boundary" 'sort_by(.created_at) | .[] | "[" + (.id | tostring) + "]" + "\n" + (.body // "") + "\n" + $b' <<<"$notes"
    } >"$file"

    # フロー: バックアップ作成
    local backup_file="$dir/__bk/issue-${iid}.md.bk"
    cp "$file" "$backup_file" || { echo "✗ バックアップの作成に失敗しました"; return 1; }

    if [[ "$is_bk_only" == "true" ]]; then
        rm -f "$file"
    else
        # フロー: Cursor で取得した Markdown を開く
        # Cursor 既存ウィンドウで開く
        cursor --reuse-window "$file" >/dev/null 2>&1 &
        disown
    fi
}
