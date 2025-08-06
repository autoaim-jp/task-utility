#!/bin/bash

share-my-script-to-github-for-saving-my-time() {
    pushd /tmp/
    rm -rf /tmp/task-utility/
    git clone git@github.com:autoaim-jp/task-utility.git
    rm -rf /tmp/task-utility/.bashrc.d/
    
    cp -r ~/monorepo/gitlab/script/bashrc-script.sh /tmp/task-utility/
    cp -r ~/monorepo/gitlab/script/register-all-label.sh /tmp/task-utility/
    cp -r ~/monorepo/gitlab/script/.bashrc.d/ /tmp/task-utility/
    cp -r ~/monorepo/.gitlab/issue_templates/ /tmp/task-utility/
    cp -r ~/monorepo/.gitlab/merge_request_templates/ /tmp/task-utility/

    cd /tmp/task-utility/
    git add .
    git commit -m 'update'
    git push origin main
    popd
}
