#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname $0)"; pwd)

function usage() {
    echo "Usage: $(basename "$0") [options] <user_name> <user_id>"
    echo "options:"
    echo "  --help    : print this message"
    echo "  --rebuild : clean up the build environment and rebuild from scratch"
    exit 1
}

REBUILD=false
while [ "$1" = --* ]; do
    case $1 in
        --help)
            usage
            ;;
        --rebuild)
            REBUILD=true
            OPT_REBUILD="--rebuild"
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

if [ $# -lt 2 ]; then
    usage
fi

USER_NAME=$1
USER_ID=$2

apt update
apt install -y build-essential zlib1g-dev libpcre2-dev sudo
apt install -y binutils lintian debhelper dh-make devscripts

useradd --uid $USER_ID $USER_NAME

echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME}

sudo -u ${USER_NAME} ${SCRIPT_DIR}/build_angie_inner.sh ${OPT_REBUILD}
