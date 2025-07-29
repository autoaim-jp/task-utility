#!/bin/bash

# create-gitlab-mr: GitLab の Issue から新規 MR を作成し、ブランチ切り替えまで自動化する関数
#
# Usage:
#   create-gitlab-mr <issue_number>
#
# Requirements:
#   - 環境変数 GITLAB_TOKEN が Personal Access Token を保持していること
#   - 環境変数 GITLAB_HOST  に GitLab Host を設定していること
#   - 環境変数 GITLAB_PROJ  に URL エンコード済みの Project ID を設定していること
#   - jq, curl, xdg-open がインストールされていること
#
# 処理概要:
#   1. 引数検証
#   2. Git repository のルート検出
#   3. main ブランチを fetch
#   4. default/#<issue_number> ブランチを切り出し → push
#   5. GitLab API で MR を作成
#   6. ブラウザで MR を開く
create-gitlab-mr() {
    local issue="$1"

    # フロー: 引数検証
    [[ -z "$issue" ]] && { echo "Usage: create-gitlab-mr <issue_number>" >&2; return 1; }

    # フロー: Git ルート取得
    local root
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    # フロー: ブランチ名決定
    local branch="default/#$issue"

    # フロー: main を最新化
    git -C "$root" fetch origin || { echo "✗ git fetch 失敗"; return 1; }

    # フロー: ブランチ作成 (origin/main から)
    git -C "$root" checkout -B "$branch" "origin/main" \
        || { echo "✗ git checkout 失敗"; return 1; }

    # フロー: ブランチ push
    git -C "$root" push -u origin "$branch" \
        || { echo "✗ git push 失敗"; return 1; }

    # フロー: GITLAB_TOKEN 確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定"; return 1; }

    # フロー: MR テンプレート読み込み
    local template_path="$root/.gitlab/merge_request_templates/default.md"
    local description
    if [[ -f "$template_path" ]]; then
        description="$(cat "$template_path")"
    else
        description="Resolve #$issue"
    fi

    # フロー: タイトル決定
    local issue_data=$(curl -sfS -H "PRIVATE-TOKEN:$GITLAB_TOKEN" \
        "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$issue") || return 1
    local title="Resolve: $(jq -r '.title' <<<"$issue_data")"

    # フロー: GitLab API で MR 作成
    local response
    response=$( \
        curl -sfS -X POST \
            -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
            --data "$(jq -n \
                --arg sb "$branch" \
                --arg tb "main" \
                --arg title "$title" \
                --arg desc "$description" \
                '{source_branch:$sb, target_branch:$tb, title:$title, description:$desc, remove_source_branch:true}')" \
            "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/merge_requests" \
    ) || { echo "✗ API 失敗"; return 1; }

    local mr_iid
    mr_iid="$(echo "$response" | jq -r '.iid')"

    echo "✓ MR !${mr_iid} を作成しました"

    # フロー: ブラウザで MR を開く
    nohup xdg-open "$GITLAB_HOST/$GITLAB_PROJ_RAW/-/merge_requests/$mr_iid" >/dev/null 2>&1 &
    disown

    # 既にブランチにいるため切り替え完了メッセージのみ
    echo "✓ ブランチ切り替え完了 ($branch)"
} 