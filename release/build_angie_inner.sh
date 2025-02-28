#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname $0)"; pwd)
ROOT=$(cd "${SCRIPT_DIR}/.."; pwd)

function usage() {
    echo "Usage: $(basename "$0") [options]"
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
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

cd "${SCRIPT_DIR}"
if [ ${REBUILD} = true ]; then
    rm -rf third-party
fi
mkdir -p third-party
cd third-party

echo -e "\n  ... Building quictls at ${PWD}/quictls ...\n"
if [ ${REBUILD} = true ] || [ ! -e quictls ]; then
    git clone --depth 1 https://github.com/quictls/openssl quictls
    cd quictls
    git fetch --unshallow
else
    echo "       .. directory ${SCRIPT_DIR}/third-party/quicktls already exists, skipping checkout"
    cd quictls
fi
git fetch
if [ ${REBUILD} = true ] || [ ! -e install/lib/libssl.a ]; then
    ./Configure --release
    make
    mkdir -p install/lib
    cp -r include install/
    cp libssl.a libcrypto.a install/lib/
else
    echo "       .. found arifacts, skipping the build"
fi
echo -e "\n  ... Built quictls successfully at ${PWD}/quictls ...\n"

cd "${ROOT}"
./configure \
    --with-cc-opt="-O2 -I${SCRIPT_DIR}/third-party/quictls/install/include" \
    --with-ld-opt="-L${SCRIPT_DIR}/third-party/quictls/install/lib" \
    --prefix=/etc/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --lock-path=/var/run/nginx.lock \
    --modules-path=/usr/lib/nginx/modules \
    --pid-path=/var/run/nginx.pid \
    --sbin-path=/usr/sbin/angie \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --user=nginx \
    --group=nginx \
    --with-file-aio \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_mqtt_preread_module \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-threads
make
sudo make install

echo -e "\n  ... Built angie successfully at ${PWD}/angie ...\n"
cd "${SCRIPT_DIR}"
LATEST_ANGIE_TAG=$(git tag -l | sort -V | tail -n 1)
ANGIE_VERSION=$(echo ${LATEST_ANGIE_TAG} | sed 's/Angie-//g')
rm -rf angie-bios_*
mkdir -p angie-bios_${ANGIE_VERSION}/DEBIAN
cd angie-bios_${ANGIE_VERSION}

echo "Package: angie-bios
Version: ${ANGIE_VERSION}
Maintainer: bios dev
Architecture: all
Description: angie built for bios" > DEBIAN/control

echo "useradd nginx" > DEBIAN/postinst
chmod +x DEBIAN/postinst

mkdir -p ./etc
cp -pr /etc/nginx ./etc/nginx
mkdir -p ./var/log/nginx
mkdir -p ./var/cache/nginx
mkdir -p ./usr/sbin
cp -p /usr/sbin/angie ./usr/sbin/
cd ./usr/sbin
ln -s angie nginx
cd ../../..
dpkg-deb --build angie-bios_${ANGIE_VERSION}
