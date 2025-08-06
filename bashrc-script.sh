# 以下を .bashrc に追加
# GITLAB_TOKEN は個人アクセストークンを書く。

# linuxのみ設定。適宜変更。
alias cursor="~/Applications/Cursor-*.AppImage"

GITLAB_HOST="https://my-gitlab-host.example.com"
GITLAB_PROJ_RAW="my-group/my-monorepo"
# URL エンコード (“/” → “%2F”) my-group/my-monorepo → my-group%2Fmy-monorepo
GITLAB_PROJ=$(echo "$GITLAB_PROJ_RAW" | sed 's|/|%2F|g')
GITLAB_TOKEN="<ここに個人アクセストークンを設定>"

for file in "$HOME/.bashrc.d/"*.sh; do
    [ -r "$file" ] && source "$file"
done

alias cgis="create-gitlab-issue"
alias ggis="get-gitlab-issue"
alias ugis="update-gitlab-issue"
alias ggmrb="get-gitlab-mr-body"
alias ugmrb="update-gitlab-mr-body"
alias cgms="create-gitlab-milestone"
alias dgmsbp="delete-gitlab-milestone-by-prefix"
alias lgmsbp="close-gitlab-milestone-by-prefix"
alias cgmr="create-gitlab-mr"
alias clis="create-local-issue"
