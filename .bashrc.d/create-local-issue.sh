#!/bin/bash

create-local-issue() {
    local template_name="$1"
    local target_name="$2"
    
    # フロー: 引数検証
    [[ -z "$template_name" ]] && { echo "Usage: create-local-issue <template_name> <target_name>" >&2; return 1; }
    [[ -z "$target_name" ]] && { echo "Usage: create-local-issue <template_name> <target_name>" >&2; return 1; }

    local root
    # フロー: Git ルート取得
    root="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
        || { echo "✗ git 管理下で実行してください"; return 1; }

    local template_file="$root/.gitlab/issue_templates/${template_name}.md"

    # #259 更新: issue-###-タイトル.md
    local file_pattern="$root/__download/issue-${target_name}-.+\.md"
    local file_count=$(find "$root/__download" -type f -regex "$file_pattern" | wc -l)

    local target_file="$root/__download/issue-${target_name}-${template_name}.md"

    # フロー: テンプレートファイル存在確認
    if [[ ! -f "$template_file" ]]; then
        echo "✗ $template_file がありません"; return 1;
    fi

    # フロー: コピー先ファイル存在確認（既に存在していたらエラー）
    if [[ "$file_count" -ne 0 ]]; then
        echo "✗ issue-${target_name}-から始まるファイルが既に存在します"; return 1;
    fi

    # フロー: テンプレートをコピー
    cp "$template_file" "$target_file" \
        || { echo "✗ ファイルのコピーに失敗しました"; return 1; }

    echo "✓ ${template_name}.mdをissue-${target_name}-${template_name}.mdにコピーしました"

    # フロー: 先頭に指示欄を追加
    local temp_file
    temp_file="$(mktemp)"
    {
        echo "### AIへのissue作成指示"
        echo "作成指示を受けてこのissueを埋める際、AIへのissue作成指示セクションは消してください。"
        echo "(ここにissueの方針を記載してください)"
        echo ""
        cat "$target_file"
    } > "$temp_file"

    mv "$temp_file" "$target_file" \
        || { echo "✗ 指示欄の追加に失敗しました"; return 1; }

    echo "✓ issue-${target_name}-${template_name}.mdの先頭に指示欄を作成しました。"

    # #259 追加: Cursor で開く
    # フロー: Cursor で取得した Markdown を開く
    cursor --reuse-window "$target_file" >/dev/null 2>&1 &
    disown
}
