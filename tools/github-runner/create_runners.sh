#!/bin/bash

RUNNERS=(
       136.144.55.87
       136.144.55.243
       139.178.69.151)

VIPS=(
    147.75.89.176/28
    147.75.108.64/28
    147.75.202.0/28)

TOKEN=$1

if [ -z "$1" ]; then
     echo "USAGE: sh ./create_runners.sh <GITHUB_RUNNER_TOKEN>"
     exit 1
fi


RUNNER_COUNT=0
for node in "${!RUNNERS[@]}"; do
    export RUNNER_IMAGE="conformance/github-runner:v2.336.0" # don't forget the v
    ssh root@${RUNNERS[$node]} "docker pull $RUNNER_IMAGE"
    RUNNERS_PER_NODE=4
    until [ $RUNNERS_PER_NODE -eq 0 ]; do
        ssh root@${RUNNERS[$node]} "docker run -d --network host --restart always --name github-runner$RUNNER_COUNT -e REPO_URL="https://github.com/lfn-cnti/testsuite" -e RUNNER_NAME="runner$RUNNER_COUNT" -e RUNNER_TOKEN="$TOKEN" -e RUNNER_WORKDIR="/github-runner-cnf-testsuite" -e LABELS="v1.0.0" -v /var/run/docker.sock:/var/run/docker.sock -v /runner-tmp/runner$RUNNER_COUNT:/tmp -v /github-runner-cnf-testsuite/cnf-testsuite/cnf-testsuite/tools:/docker-host-repo/tools -v /shared:/shared $RUNNER_IMAGE"
        RUNNER_COUNT=$(($RUNNER_COUNT + 1))
        RUNNERS_PER_NODE=$(($RUNNERS_PER_NODE - 1))
    done
    ssh root@${RUNNERS[$node]} "docker network rm kind"
    ssh root@${RUNNERS[$node]} docker network create --driver bridge --subnet=${VIPS[$node]} --opt "com.docker.network.bridge.name"="kindbridge" --opt "com.docker.network.bridge.enable_ip_masquerade"="false" kind
    ssh root@${RUNNERS[$node]} sudo chmod 777 /runner-tmp -R
    # ssh root@${RUNNERS[$node]} "sudo apt update && sudo apt install -y bridge-utils"
   # ssh root@${RUNNERS[$node]} "sudo brctl addif kindbridge bond0"
done

