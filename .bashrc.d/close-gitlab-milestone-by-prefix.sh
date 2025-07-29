#!/bin/bash

# close-gitlab-milestone-by-prefix
#   指定した prefix で始まる GitLab マイルストーンのうち、
#   期限が過ぎたものを期限の古い順に処理します。
#   ・open 状態の issue を次のマイルストーン (未来で最も近い期限) へ移動
#   ・次のマイルストーンが存在しない場合はデフォルトマイルストーンへ移動
#   ・マイルストーン自体は close する
#
# 依存環境変数:
#   GITLAB_HOST  GitLab サーバ (例: https://gitlab.example.com)
#   GITLAB_PROJ  プロジェクト ID  (例: 123456)
#   GITLAB_TOKEN PRIVATE-TOKEN
#
# 使い方:
#   close-gitlab-milestone-by-prefix <prefix>
#   例) close-gitlab-milestone-by-prefix "xlogin"

close-gitlab-milestone-by-prefix() {
    # --- 引数検証 ---------------------------------------------------------
    if [[ $# -ne 1 ]]; then
        echo "Usage: close-gitlab-milestone-by-prefix <prefix>" >&2
        echo "  例: close-gitlab-milestone-by-prefix 'xlogin'" >&2
        return 1
    fi
    local prefix="$1"

    # --- 必須環境変数 -----------------------------------------------------
    for v in GITLAB_HOST GITLAB_PROJ GITLAB_TOKEN; do
        [[ -z "${!v}" ]] && { echo "✗ $v 未設定" >&2; return 1; }
    done

    # --- マイルストーン一覧取得 -----------------------------------------
    local api_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones?state=active&per_page=100"
    echo "プレフィックス '[${prefix}]' で始まるアクティブマイルストーンを取得しています..."
    local milestones_json
    milestones_json=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$api_url") || { echo "✗ API 失敗" >&2; return 1; }

    # --- デフォルトマイルストーン確認/作成 -------------------------------
    local default_milestone_id=""
    while IFS= read -r m; do
        local title id
        title=$(echo "$m" | jq -r '.title // empty')
        if [[ "$title" == "[${prefix}]" ]]; then
            id=$(echo "$m" | jq -r '.id')
            default_milestone_id="$id"
            break
        fi
    done < <(echo "$milestones_json" | jq -c '.[]')

    if [[ -z "$default_milestone_id" ]]; then
        echo "デフォルトマイルストーンが存在しません。作成します..."
        local create_resp create_http
        create_resp=$(curl -s -w "\n%{http_code}" \
            -X POST \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"title\": \"[${prefix}]\"}" \
            "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones")
        create_http=$(echo "$create_resp" | tail -n 1)
        if [[ "$create_http" -ne 201 ]]; then
            echo "❌ マイルストーンの作成に失敗しました (HTTP $create_http)" >&2
            echo "レスポンス: $(echo "$create_resp" | head -n -1)" >&2
            return 1
        fi
        default_milestone_id=$(echo "$create_resp" | head -n -1 | jq -r '.id')
        echo "✅ デフォルトマイルストーン作成成功 (ID: $default_milestone_id)"
    else
        echo "デフォルトマイルストーン ID: $default_milestone_id を使用します。"
    fi

    # --- prefix マイルストーン抽出 & 整形 -------------------------------
    # 期限が設定されているもののみ対象 (due_date != null)
    local milestones_to_process=()
    while IFS= read -r m; do
        local id title due_date
        id=$(echo "$m" | jq -r '.id')
        title=$(echo "$m" | jq -r '.title')
        due_date=$(echo "$m" | jq -r '.due_date')
        # デフォルトマイルストーン([prefix]) と due_date が null のものを除外
        if [[ "$title" == "[${prefix}]"* && "$title" != "[${prefix}]" && "$due_date" != "null" && -n "$due_date" ]]; then
            milestones_to_process+=("$id:$title:$due_date")
        fi
    done < <(echo "$milestones_json" | jq -c '.[]')

    if [[ ${#milestones_to_process[@]} -eq 0 ]]; then
        echo "対象マイルストーンが見つかりません。処理を終了します。"
        return 0
    fi

    # --- ソート (期限の古い順) ------------------------------------------
    IFS=$'\n' milestones_to_process=( $(printf "%s\n" "${milestones_to_process[@]}" | sort -t ':' -k3,3) )
    unset IFS

    # --- 本日の日付 (UTC 的なずれを小さくするため -u オプション無し) ------
    local today
    today=$(date +%F)
    local today_epoch
    today_epoch=$(date -d "$today" +%s)

    # --- 実行対象を抽出 (期限が今日以前) ---------------------------------
    local filtered=()
    for m in "${milestones_to_process[@]}"; do
        local id title due
        id="${m%%:*}"
        local rest="${m#*:}"
        title="${rest%%:*}"
        due="${m##*:}"
        local due_epoch
        due_epoch=$(date -d "$due" +%s)
        if [[ $due_epoch -le $today_epoch ]]; then
            filtered+=("$id:$title:$due")
        fi
    done

    if [[ ${#filtered[@]} -eq 0 ]]; then
        echo "期限が過ぎたマイルストーンはありません。処理を終了します。"
        return 0
    fi

    # --- 実行確認 --------------------------------------------------------
    echo "以下のマイルストーンを処理します (期限の古い順):"
    echo "----------------------------------------"
    for m in "${filtered[@]}"; do
        local id title due
        id="${m%%:*}"
        local rest="${m#*:}"
        title="${rest%%:*}"
        due="${m##*:}"
        echo "ID: $id | タイトル: $title | 期限: $due"
    done
    echo "----------------------------------------"
    echo "open issue を次のマイルストーンまたはデフォルトマイルストーンに移動し、対象マイルストーンを close します。"

    read -p "実行しますか？ (y/N) " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "処理をキャンセルしました。"
        return 0
    fi

    # --- メイン処理 ------------------------------------------------------
    local moved=0 closed=0 failed=0
    local total=${#filtered[@]}
    for ((i=0; i<total; i++)); do
        local curr="${filtered[i]}"
        local id title due
        id="${curr%%:*}"
        local rest="${curr#*:}"
        title="${rest%%:*}"
        due="${curr##*:}"

        # --- 次のマイルストーンを決定 -----------------------------------
        local target_milestone_id=""
        if (( i+1 < ${#milestones_to_process[@]} )); then
            local next="${milestones_to_process[i+1]}"
            target_milestone_id="${next%%:*}"
        else
            target_milestone_id="$default_milestone_id"
        fi

        echo "target_milestone_id: $target_milestone_id"

        # --- open issue を取得 -----------------------------------------
        local issues_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones/$id/issues?state=opened&per_page=100"
        local issues_json
        issues_json=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$issues_url")

        while IFS= read -r issue; do
            local iid
            iid=$(echo "$issue" | jq -r '.iid')
            state=$(echo "$issue" | jq -r '.state')
            [[ -z "$iid" || "$iid" == "null" || "$state" == "closed" ]] && continue
            local update_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid"
            local up_resp up_http
            up_resp=$(curl -s -w "\n%{http_code}" -X PUT \
                -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"milestone_id\": $target_milestone_id}" \
                "$update_url")
            up_http=$(echo "$up_resp" | tail -n 1)
            if [[ "$up_http" -eq 200 ]]; then
                ((moved++))
            else
                echo "❌ issue #$iid のマイルストーン変更に失敗 (HTTP $up_http)" >&2
            fi
        done < <(echo "$issues_json" | jq -c '.[]')

        # --- マイルストーンを close ------------------------------------
        local close_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones/$id"
        local resp http_code
        resp=$(curl -s -w "\n%{http_code}" -X PUT \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"state_event\": \"close\"}" \
            "$close_url")
        http_code=$(echo "$resp" | tail -n 1)
        if [[ "$http_code" -eq 200 ]]; then
            echo "✅ Closed: $title (ID: $id)"
            ((closed++))
        else
            echo "❌ Close 失敗: $title (ID: $id) - HTTP $http_code" >&2
            ((failed++))
        fi
    done

    # --- 結果 -----------------------------------------------------------
    echo "\n処理完了:"
    echo "  issue 移動: $moved 件"
    echo "  close 成功: $closed 件"
    echo "  close 失敗: $failed 件"

    echo "デフォルトマイルストーンのページを開きます"
    nohup xdg-open "$GITLAB_HOST/$GITLAB_PROJ_RAW/-/milestones/$default_milestone_id" >/dev/null 2>&1 &
    disown

    [[ $failed -eq 0 ]]
} 