#!/bin/bash

# ラベル定義
declare -a labels=(
    '{"name":"ADR（決定事項）","color":"#dfdfdf","description":"決定事項、決めごと"}'
    '{"name":"Child（子issue）","color":"#000000","description":""}'
    '{"name":"Parent（親issue）","color":"#000000","description":""}'
    '{"name":"Project-Document（書類）","color":"#330066","description":""}'
    '{"name":"Spec-Document（仕様書）","color":"#8fbc8f","description":""}'
    '{"name":"output::code（プログラミングする）","color":"#6c5ce7","description":"ソースコードをを書くことを想定する"}'
    '{"name":"output::document（git管理下にドキュメントを作る）","color":"#00b894","description":"git管理下にドキュメントを作ることを想定する"}'
    '{"name":"output::infra（環境設定、GitLab設定）","color":"#fdcb6e","description":"インフラ設定をする、GitLabの設定をすることを想定する"}'
    '{"name":"output::issue（Issueを残す）","color":"#e17055","description":"issueページにしっかり文章を書くことを想定する"}'
    '{"name":"pj::xlogin（個人開発）","color":"#6699cc","description":""}'
    '{"name":"status::doing（実施中）","color":"#ff6b6b","description":"実施中"}'
    '{"name":"status::inbox（新規追加）","color":"#4ecdc4","description":"思いつき"}'
    '{"name":"status::memo（メモ）","color":"#36454f","description":""}'
    '{"name":"status::ready（作業したい）","color":"#45b7d1","description":"準備完了"}'
    '{"name":"status::skipped（あまりやる気ない）","color":"#ffeaa7","description":"7日間放置"}'
    '{"name":"status::suspended（いつかやるけど保留）","color":"#dda0dd","description":"保留"}'
    '{"name":"type::bug（バグ修正をする）","color":"#d63031","description":"バグ修正"}'
    '{"name":"type::chore（その他の作業をする）","color":"#636e72","description":"雑務"}'
    '{"name":"type::docs（文章を書く）","color":"#74b9ff","description":"ドキュメント"}'
    '{"name":"type::feature（つくる、新機能を実装する）","color":"#00b894","description":"新機能"}'
    '{"name":"type::idea（思いつきをissueで整理する）","color":"#6c5ce7","description":"アイデア"}'
)

# ラベル作成
for label in "${labels[@]}"; do
    echo "Creating label: $(echo $label | jq -r '.name')"
    curl --request POST \
         --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
         --header "Content-Type: application/json" \
         --data "$label" \
         "$GITLAB_HOST/api/v4/projects/$GITLAB_PROJ/labels"
    echo -e "\n"
done
