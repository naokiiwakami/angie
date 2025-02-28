#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname $0)"; pwd)
ROOT=$(cd "${SCRIPT_DIR}/.."; pwd)

docker run --rm --name angie-build -v ${ROOT}:${ROOT} \
    ubuntu:22.04 ${SCRIPT_DIR}/build_angie_outer.sh $(whoami) $(id -u)
