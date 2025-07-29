#!/bin/bash

share-my-script-to-github-for-saving-my-time() {
    pushd /tmp/
    rm -rf /tmp/task-utility/
    git clone git@github.com:autoaim-jp/task-utility.git
    rm -rf /tmp/task-utility/.bashrc.d/
    cp -r ~/monorepo/gitlab/script/.bashrc.d/ /tmp/task-utility/
    cd /tmp/task-utility/
    git add .
    git commit -m 'update'
    git push origin main
    popd
}
