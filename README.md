# task-utility
タスク管理のため私物を共有


### .bashrcの設定例

```
GITLAB_HOST="https://<自身のGitLabのurl>"
GITLAB_PROJ_RAW="<group_name>/<repo_name>"
# URL エンコード済み (“/” → “%2F”)
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
alias dgmsp="delete-gitlab-milestone-by-prefix"
alias lgmsbp="close-gitlab-milestone-by-prefix"
alias cgmr="create-gitlab-mr"
```
