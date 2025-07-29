#!/bin/bash

update-gitlab-issue() {
    # フロー: タイトル/本文/コメントを更新するサブ関数を定義
    update-issue-title-description-comment() {
        local iid="$1"
        local file_index="$2"
        local note_id="$3"
        [[ -z "$iid" ]] && { echo "Usage: update-issue-title-description-comment <issue_number> <file_index> <note_id>" >&2; return 1; }
        [[ -z "$file_index" ]] && { echo "Usage: update-issue-title-description-comment <issue_number> <file_index> <note_id>" >&2; return 1; }
        [[ -z "$note_id" ]] && { echo "Usage: update-issue-title-description-comment <issue_number> <file_index> <note_id>" >&2; return 1; }

        local file="$dir/__split/issue_${iid}/new/${file_index}"
        [[ -f "$file" ]] || { echo "✗ $file がありません" >&2; return 1; }

        local body
        body="$(tail -n +2 "$file")"
        [[ -z "$body" ]] && { echo "✗ 投稿する内容が空です" >&2; return 1; }

        case "$note_id" in
            "タイトル")
                curl -sfS -X PUT \
                -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
                --data "$(jq -Rn --arg b "$body" '{title:$b}')" \
                "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid" \
                >/dev/null 2>&1 \
                || { echo "✗ API 失敗 タイトル" >&2; return 1; }
                echo "✓ タイトル #${iid} を更新しました。" >&2
                ;;
            "本文")
                curl -sfS -X PUT \
                -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
                --data "$(jq -Rn --arg b "$body" '{description:$b}')" \
                "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid" \
                >/dev/null 2>&1 \
                || { echo "✗ API 失敗 本文" >&2; return 1; }
                echo "✓ 本文 #${iid} を更新しました。" >&2
                ;;
            *)
                curl -sfS -X PUT \
                -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
                --data "$(jq -Rn --arg b "$body" '{body:$b}')" \
                "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid/notes/$note_id" \
                >/dev/null 2>&1 \
                || { echo "✗ API 失敗 コメント" >&2; return 1; }
                echo "✓ コメント #${iid} [${note_id}] を更新しました。" >&2
                ;;
        esac

    }

    # フロー: コメント投稿サブ関数を定義
    post-issue-comment() {
        local iid="$1"
        local file_index="$2"
        [[ -z "$iid" ]] && { echo "Usage: post-issue-comment <issue_number> <file_index>" >&2; return 1; }
        [[ -z "$file_index" ]] && { echo "Usage: post-issue-comment <issue_number> <file_index>" >&2; return 1; }

        local file="$dir/__split/issue_${iid}/new/${file_index}"
        [[ -f "$file" ]] || { echo "✗ $file がありません" >&2; return 1; }

        local body
        body="$(cat "$file")"
        [[ -z "$body" ]] && { echo "✗ 投稿する内容が空です" >&2; return 1; }

        # コメントを投稿し、レスポンスから note_id を取得
        local response
        response=$(curl -sfS -X POST \
            -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
            --data "$(jq -Rn --arg b "$body" '{body:$b}')" \
            "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid/notes" 2>/dev/null) \
            || { echo "✗ API 失敗" >&2; return 1; }

        local note_id
        note_id=$(echo "$response" | jq -r '.id')
        echo "✓ コメント [${file_index}] を投稿しました。 (note_id: $note_id)" >&2

        # 戻り値として、note_id を返す
        echo "$note_id"
    }

    # フロー: コメント削除サブ関数を定義
    delete-issue-comment() {
        local iid="$1"
        local note_id="$2"
        [[ -z "$iid" ]] && { echo "Usage: delete-issue-comment <issue_number> <note_id>" >&2; return 1; }
        [[ -z "$note_id" ]] && { echo "Usage: delete-issue-comment <issue_number> <note_id>" >&2; return 1; }

        case "$note_id" in
            "タイトル")
                echo "タイトルは削除できません" >&2
                ;;
            "本文")
                echo "本文は削除できません" >&2
                ;;
            *)
                curl -sfS -X DELETE \
                -H "PRIVATE-TOKEN:$GITLAB_TOKEN" -H "Content-Type: application/json" \
                "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/issues/$iid/notes/$note_id" \
                >/dev/null 2>&1 \
                || { echo "✗ API 失敗 コメント" >&2; return 1; }
                echo "✓ コメント #${iid} [${note_id}] を削除しました。" >&2
                ;;
        esac
    }

    # フロー: バウンダリで Markdown を分割し new/bk ディレクトリに展開する関数を定義
    split_file_by_boundary() {
        local file="$1"
        local iid="$2"
        local file_dir="$3"
        
        # バウンダリを取得
        local boundary
        boundary=$(head -n 1 "$file")
        [[ "$boundary" != "##### -boundary-"* ]] && { echo "✗ バウンダリが見つかりません" >&2; return 1; }

        mkdir -p "$file_dir"

        awk -v boundary="$boundary" -v file_dir="$file_dir" '
        BEGIN { file_index = 0; }
        $0 == boundary {
            if (file_index > 0) close(current_file_path);
            file_index++;
            current_file_path = file_dir file_index ".md";
            next;
        }
        { print > current_file_path; }
        ' "$file"
    }


    # フロー: 引数検証
    local iid="$1"
    [[ -z "$iid" ]] && { echo "Usage: post-gitlab-issue-comment <issue_number>" >&2; return 1; }

    # #132 追加
    # iidが数字でない場合は、新規issue作成コマンドと間違えた可能性がある
    if [[ ! "$iid" =~ ^[0-9]+$ ]]; then
        echo "✗ 数字が渡されたため、新規issue作成コマンドと間違えた可能性があります" >&2
        echo "✗ 新規issueを作成したい場合は、`create-gitlab-issue` を使用してください" >&2
        return 1
    fi

    local root
    # フロー: Git ルート取得
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください" >&2; return 1; }

    # フロー: 各種パス設定
    local dir="$root/__download"
    local file="$dir/issue_${iid}.md"
    local backup_file="$dir/__bk/issue_${iid}.md.bk"
    local split_dir="$dir/__split/"

    # 作成・更新したコメントの note_id を格納する配列
    local note_id_list=()

    # フロー: バックアップファイル存在確認 & なければ自動取得
    [[ -f "$file" ]] || { echo "✗ $file がありません" >&2; return 1; }
    if [[ ! -f "$backup_file" ]]; then
        echo "✗ $backup_file がありません。取得します。" >&2
        get-gitlab-issue "$iid" "true"
    fi

    # #132 追加
    # バックアップファイルがない場合は、issueが存在しないため異常終了
    if [[ ! -f "$backup_file" ]]; then
        echo "✗ $iid のバックアップファイルを取得できませんでした" >&2
        return 1
    fi

    # フロー: GITLAB_TOKEN 確認
    [[ -z "$GITLAB_TOKEN" ]] && { echo "✗ GITLAB_TOKEN 未設定" >&2; return 1; }

    # フロー: バウンダリで分割 --------------------------------------------
    split_file_by_boundary "$file"  "$iid" "$split_dir/issue_$iid/new/"
    split_file_by_boundary "$backup_file" "$iid" "$split_dir/issue_$iid/bk/"


    # フロー: 分割ファイルの差分比較 & 処理ループ
    # 分割したファイルを diff で比較し、ファイルごとに処理 ------------------
    local new_dir="$split_dir/issue_$iid/new"
    local bk_dir="$split_dir/issue_$iid/bk"

    # 2 つのディレクトリに存在するファイル名をユニークに抽出
    mapfile -t file_list < <( {
        [ -d "$new_dir" ] && ls "$new_dir";
        [ -d "$bk_dir" ] && ls "$bk_dir"; } 2>/dev/null | sort -u )

    if [[ ${#file_list[@]} -eq 0 ]]; then
        echo "差分を比較するファイルが見つかりません。" >&2
    fi

    local has_any_diff="false"
    local skipped_any="false"
    for file_index in "${file_list[@]}"; do
        local new_file="$new_dir/$file_index"
        local old_file="$bk_dir/$file_index"

        local diff_output=""
        local mode=""
        local note_id="(post)"

        # フロー: ファイルの差分の種類判定
        if [[ $(grep -cv '^[[:space:]]*$' "$new_file") -eq 0 ]] && [[ -s "$old_file" ]]; then
            # 新しいファイルが空または改行のみで、旧ファイルは中身がある場合
            diff_output=$(cat "$old_file")
            mode="delete"
            note_id=$(awk '/^\[.*\]$/{gsub(/[\[\]]/, "", $1); print $1}' "$old_file")
        elif [[ -f "$new_file" && -f "$old_file" ]]; then
            diff_output=$(diff -u "$old_file" "$new_file")
            mode="update"
            note_id=$(awk '/^\[.*\]$/{gsub(/[\[\]]/, "", $1); print $1}' "$new_file")
        elif [[ -f "$new_file" && ! -f "$old_file" ]]; then
            diff_output=$(cat "$new_file")
            mode="post"
        elif [[ ! -f "$new_file" && -f "$old_file" ]]; then
            echo "旧ファイルのみ存在するのは想定外" >&2
            return 1
        else
            echo "新しいファイルが空で、旧ファイルも空の場合は想定外" >&2
            return 1
        fi

        if [[ -n "$diff_output" ]]; then
            has_any_diff="true"
            echo "------------------------------" >&2
            echo "ファイル: $file_index" >&2
            echo "------------------------------" >&2
            echo "$diff_output" >&2

            # ユーザーに送付確認
            # フロー: ユーザー確認 → サブ関数呼び出し (update/post/delete)
            case "$mode" in
                "update")
                    echo -n "コメントを更新しますか？ (y/N) : "
                    ;;
                "post")
                    echo -n "コメントを作成しますか？ (y/N) : "
                    ;;
                "delete")
                    echo -n "コメントを削除しますか？ (y/N) : "
                    ;;
            esac
            read -r response
            if [[ "$response" == "y" ]]; then
                case "$mode" in
                    "update")
                        update-issue-title-description-comment "$iid" "$file_index" "$note_id"
                        note_id_list+=("$note_id")
                        ;;
                    "post")
                        # 戻り値は新規作成したコメントの note_id
                        note_id=$(post-issue-comment "$iid" "$file_index")
                        note_id_list+=("$note_id")
                        ;;
                    "delete")
                        delete-issue-comment "$iid" "$note_id"
                        ;;
                esac
            else
                echo "投稿をスキップしました。" >&2
                skipped_any="true"
            fi
        fi
    done

    # フロー: 差分無しの場合メッセージ表示
    if [[ "$has_any_diff" == "false" ]]; then
        echo "差分はありません。" >&2
    fi
    
    # フロー: 一時ファイル削除 & ブラウザで Issue ページを開く
    rm -rf "$split_dir/issue_$iid"
    if [[ "$skipped_any" == "false" ]]; then
        rm -f "$file"
        rm -f "$backup_file"
    else
        echo "未投稿の差分が残っています。ファイルを保持しました: $file" >&2
    fi

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

    echo "note_id_list: ${note_id_list[@]}" >&2
    
    # フロー: ブラウザで作成・更新したコメントのリンクを開く
    local decoded_proj
    decoded_proj="$(printf '%b' "${GITLAB_PROJ//%/\\x}")"

    if [[ ${#note_id_list[@]} -gt 0 ]]; then
        for nid in "${note_id_list[@]}"; do
            # note_idがタイトルまたは本文のときは、issueページを開く
            if [[ "$nid" == "タイトル" || "$nid" == "本文" ]]; then
                echo "リンクを開く $GITLAB_HOST/$decoded_proj/-/issues/$iid" >&2
                nohup xdg-open "$GITLAB_HOST/$decoded_proj/-/issues/$iid" >/dev/null 2>&1 &
            else
                echo "リンクを開く $GITLAB_HOST/$decoded_proj/-/issues/$iid#note_$nid" >&2
                nohup xdg-open "$GITLAB_HOST/$decoded_proj/-/issues/$iid#note_$nid" >/dev/null 2>&1 &
            fi
        done
    else
        echo "リンクを開く $GITLAB_HOST/$decoded_proj/-/issues/$iid" >&2
        nohup xdg-open "$GITLAB_HOST/$decoded_proj/-/issues/$iid" >/dev/null 2>&1 &
    fi
    disown
}
