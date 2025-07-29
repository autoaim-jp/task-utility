#!/bin/bash

delete-gitlab-milestone-by-prefix() {
    # マイルストーン削除コマンド
    # 使用方法: delete-gitlab-milestone-by-prefix <prefix>

    # フロー: 引数検証
    if [[ $# -ne 1 ]]; then
        echo "Usage: delete-gitlab-milestone-by-prefix <prefix>" >&2
        echo "  例: delete-gitlab-milestone-by-prefix 'xlogin'" >&2
        return 1
    fi

    local prefix="$1"

    # フロー: GITLAB_* 環境変数確認
    for v in GITLAB_HOST GITLAB_PROJ GITLAB_TOKEN; do
        [[ -z "${!v}" ]] && { echo "✗ $v 未設定" >&2; return 1; }
    done

    # フロー: マイルストーン一覧取得
    local api_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones?state=active&per_page=100"
    echo "プレフィックス '[${prefix}]' で始まるマイルストーンを検索しています..."

    local milestones
    milestones=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$api_url") || { echo "✗ API 失敗" >&2; return 1; }

    # フロー: プレフィックスでフィルタリング
    local matching_milestones=()
    while IFS= read -r milestone; do
        local title id
        title=$(echo "$milestone" | jq -r '.title // empty')
        if [[ -n "$title" && "$title" == "[${prefix}]"* ]]; then
            id=$(echo "$milestone" | jq -r '.id')
            matching_milestones+=("$id:$title")
        fi
    done < <(echo "$milestones" | jq -c '.[]')

    if [[ ${#matching_milestones[@]} -eq 0 ]]; then
        echo "マイルストーンが一つも見つかりません。処理を終了します。"
        return 0
    fi

    # フロー: プレフィックスと完全一致するマイルストーン（デフォルトマイルストーン）を検索し、なければ作成
    local target_milestone_id=""
    local to_delete=()

    for milestone in "${matching_milestones[@]}"; do
        local id="${milestone%%:*}"
        local title="${milestone#*:}"
        if [[ "$title" == "[${prefix}]" ]]; then
            target_milestone_id="$id"
        else
            to_delete+=("$id:$title")
        fi
    done

    if [[ -z "$target_milestone_id" ]]; then
        echo "デフォルトマイルストーン（プレフィックスと同名のマイルストーン）が存在しないため作成します..."
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
        target_milestone_id=$(echo "$create_resp" | head -n -1 | jq -r '.id')
        echo "✅ 作成成功: ID $target_milestone_id"
    else
        echo "デフォルトマイルストーンとして、既存のマイルストーン (ID: $target_milestone_id) を使用します。"
    fi

    matching_milestones=("${to_delete[@]}")
    if [[ ${#matching_milestones[@]} -eq 0 ]]; then
        echo "削除対象のマイルストーンはありません。デフォルトのマイルストーンのみ存在します。"
        return 0
    fi

    # フロー: 実行確認
    echo ""
    echo "以下のマイルストーンを削除し、関連する課題があれば '[${prefix}]' マイルストーン(ID: $target_milestone_id) へ移動します:"
    echo "----------------------------------------"
    for milestone in "${matching_milestones[@]}"; do
        local id="${milestone%%:*}"
        local title="${milestone#*:}"
        echo "ID: $id | タイトル: $title"
    done
    echo "----------------------------------------"
    echo ""

    read -p "課題の移動とマイルストーン削除を実行しますか？ (y/N) " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "処理をキャンセルしました。"
        return 0
    fi

    echo ""
    echo "課題を移動し、マイルストーンを削除しています..."

    local moved_count=0
    local deleted_count=0
    local failed_count=0
    # フロー: マイルストーンごとに処理
    for milestone in "${matching_milestones[@]}"; do
        local id="${milestone%%:*}"
        local title="${milestone#*:}"

        # フロー: issue取得
        local issues_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones/$id/issues?state=all&per_page=100"
        local issues
        issues=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$issues_url")

        # フロー: issueを一つずつ確認
        local has_closed_issue=false
        while IFS= read -r issue; do
            local iid
            iid=$(echo "$issue" | jq -r '.iid')

            # issueの状態を確認。issueがcloseされていれば、マイルストーン変更は不要。
            local state
            state=$(echo "$issue" | jq -r '.state')
            if [[ "$state" == "closed" ]]; then
                has_closed_issue=true
                continue
            fi

            # issueのマイルストーン変更。issueがcloseされていなければ、マイルストーンを変更する。
            [[ -z "$iid" || "$iid" == "null" ]] && continue
            local update_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid"
            local up_resp up_http
            up_resp=$(curl -s -w "\n%{http_code}" -X PUT \
                -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"milestone_id\": $target_milestone_id}" \
                "$update_url")
            up_http=$(echo "$up_resp" | tail -n 1)
            if [[ "$up_http" -eq 200 ]]; then
                ((moved_count++))
            else
                echo "❌ issue #$iid のマイルストーン変更に失敗 (HTTP $up_http)" >&2
            fi
        done < <(echo "$issues" | jq -c '.[]')

        # フロー: マイルストーン削除。ただしissueが一つでもcloseされていれば、削除ではなくcloseする。
        local resp http_code
        if [[ "$has_closed_issue" == true ]]; then
            echo "✅ マイルストーンにcloseされたissueがあるため、削除ではなくcloseします。"
            local close_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones/$id"
            resp=$(curl -s -w "\n%{http_code}" -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                -H "Content-Type: application/json" -d "{\"state_event\": \"close\"}" \
                "$close_url")
            http_code=$(echo "$resp" | tail -n 1)
        else
            echo "✅ マイルストーンにcloseされたissueがないため、削除します。"
            local delete_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones/$id"
            resp=$(curl -s -w "\n%{http_code}" -X DELETE -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$delete_url")
            http_code=$(echo "$resp" | tail -n 1)
        fi

        if [[ "$http_code" -eq 204 || "$http_code" -eq 200 ]]; then
            echo "✅ 処理成功: $title (ID: $id)"
            ((deleted_count++))
        else
            echo "❌ 処理失敗: $title (ID: $id) - HTTP $http_code" >&2
            echo "   $(echo "$resp" | head -n -1)" >&2
            ((failed_count++))
        fi
    done

    # フロー: 結果出力
    echo ""
    echo "処理完了:"
    echo "  issue移動: $moved_count 件"
    echo "  削除成功: $deleted_count 件"
    echo "  削除失敗: $failed_count 件"

    echo "デフォルトマイルストーンのページを開きます"
    # フロー: デフォルトマイルストーンを開く
    nohup xdg-open "$GITLAB_HOST/$GITLAB_PROJ_RAW/-/milestones/$target_milestone_id" >/dev/null 2>&1 &
    disown

    [[ $failed_count -eq 0 ]]
}
