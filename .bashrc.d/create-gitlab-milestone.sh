#!/bin/bash

create-gitlab-milestone() {
    # フロー: 期間を日数へ変換する関数を定義
    convert_to_days() {
        local _period="$1" _days=0
        # 半年 → 6ヶ月 に正規化
        [[ "$_period" == "半年" ]] && _period="6ヶ月"
        if [[ "$_period" =~ ^([0-9]+)(週間|ヶ月|か月|ケ月|週|月|年)$ ]]; then
            local _num="${BASH_REMATCH[1]}" _unit="${BASH_REMATCH[2]}"
            case "$_unit" in
                "週"|"週間") _days=$((_num * 7)) ;;
                "ヶ月"|"か月"|"ケ月"|"月") _days=$((_num * 30)) ;;
                "年") _days=$((_num * 365)) ;;
            esac
        elif [[ "$_period" =~ ^[0-9]+$ ]]; then
            _days="$_period"
        else
            echo "✗ 無効な期間形式です: $_period" >&2
            echo "   使用可能な形式: 日数(数字), 4週間, 2ヶ月, 1年 など" >&2
            return 1
        fi
        echo "$_days"
    }

    # フロー: 引数検証
    if [[ $# -ne 3 ]]; then
        echo "Usage: create-gitlab-milestone <project_name|- (use \$DEFAULT_PROJECT_NAME)> <period> <goal>" >&2
        echo "  例: create-gitlab-milestone xlogin 120 'テスト環境を整え、基盤のテストを実施'" >&2
        echo "  例: create-gitlab-milestone - 4週間 'テスト環境を整え、基盤のテストを実施' (DEFAULT_PROJECT_NAME=xlogin の場合)" >&2
        return 1
    fi

    # フロー: プロジェクト名補完
    local project_name
    if [[ "$1" == "-" && -n "$DEFAULT_PROJECT_NAME" ]]; then
        project_name="$DEFAULT_PROJECT_NAME"
    else
        project_name="$1"
    fi

    if [[ -z "$project_name" || "$project_name" == "-" ]]; then
        echo "✗ プロジェクト名が指定されていません (DEFAULT_PROJECT_NAME も未設定)" >&2
        return 1
    fi

    local period="$2"
    local goal="$3"

    local total_days
    total_days=$(convert_to_days "$period") || return 1
    echo "期間 '$period' を ${total_days}日と判定"

    # フロー: GITLAB_* 環境変数確認
    for v in GITLAB_HOST GITLAB_PROJ GITLAB_TOKEN; do
        [[ -z "${!v}" ]] && { echo "✗ $v 未設定" >&2; return 1; }
    done

    # フロー: 日付計算
    local start_date half_days due_date due_date_fmt
    start_date="$(date +%Y-%m-%d)"
    half_days=$(( total_days / 2 ))
    due_date="$(date -d "+${half_days} days" +%Y-%m-%d)"
    due_date_fmt="$(date -d "+${half_days} days" +%Y/%m/%d)"

    # フロー: タイトル生成
    local title="[${project_name}] ${due_date_fmt} ${goal}"

    echo "--- マイルストーン作成 -----------------------------------------"
    echo "プロジェクト  : $project_name"
    echo "入力期間      : $period"
    echo "総日数        : $total_days"
    echo "期限日数      : $half_days"
    echo "開始日        : $start_date"
    echo "期限日        : $due_date"
    echo "タイトル      : $title"
    echo "目標          : $goal"

    # フロー: GitLab API: POST /milestones
    local api_url="$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/milestones"
    local response http_code response_body

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"$title\", \"description\": \"$goal\", \"start_date\": \"$start_date\", \"due_date\": \"$due_date\"}" \
        "$api_url")

    response_body=$(echo "$response" | head -n -1)
    http_code=$(echo "$response" | tail -n 1)

    # フロー: 結果出力
    if [[ "$http_code" -eq 201 ]]; then
        echo "✅ マイルストーンが作成されました"
        echo "$response_body" | jq -r '. | "ID: \(.id)\nタイトル: \(.title)\n開始日: \(.start_date)\n期限日: \(.due_date)\nWebURL: \(.web_url)"'
    else
        echo "❌ マイルストーンの作成に失敗しました (HTTP $http_code)" >&2
        echo "レスポンス: $response_body" >&2
        return 1
    fi
}
