#!/bin/sh
set -e

getServiceIP () {
    for arg
    do nslookup "$arg" 2>/dev/null | tail -n 9 | grep -oE '(([0-9]{1,3})\.){3}(1?[0-9]{1,3})'
    done
}

waitOrFail () {
    maxTries=24
    i=0
    while [ $i -lt $maxTries ]; do
        outStr="$($@)"
        if [ $? -eq 0 ];then
            echo "$outStr"
            return
        fi
        i=$((i+1))
        echo "==> waiting for a dependent service $i/$maxTries" >&2
        sleep 5
    done
    echo "Too many failed attempts" >&2
    exit 1
}

UNBOUND_SERVICE_HOST=${UNBOUND_SERVICE_HOST-"1.1.1.1"}
UNBOUND_SERVICE_PORT=${UNBOUND_SERVICE_PORT-"53"}
DOH_PROXY_SERVICE_HOST=${DOH_PROXY_SERVICE_HOST-"127.0.0.1"}
DOH_PROXY_SERVICE_PORT=${DOH_PROXY_SERVICE_PORT-"3000"}

if [ ! -f /opt/ssl/dhparam.pem ]; then
    openssl dhparam -out /opt/ssl/dhparam.pem 4096
fi

while getopts "h?dr" opt; do
    case "$opt" in
        h|\?)
            echo "-d  domain lookup for service discovery";
            echo "-r  uncomment lines in haproxy.conf with the word 'redirect' in them";
            exit 0
        ;;
        d)
            UNBOUND_SERVICE_HOST="$(waitOrFail getServiceIP unbound)"
            DOH_PROXY_SERVICE_HOST="$(waitOrFail getServiceIP doh-proxy m13253-doh)"
        ;;
        r)
            sed -i '/^#.* redirect /s/^#//' /etc/haproxy.conf
        ;;
    esac
done
shift $((OPTIND-1))
export RESOLVER="$UNBOUND_SERVICE_HOST:$UNBOUND_SERVICE_PORT"
export DOH_SERVER="$DOH_PROXY_SERVICE_HOST:$DOH_PROXY_SERVICE_PORT"

sed -i -e "s/server doh-proxy .*/server doh-proxy ${DOH_SERVER}/" \
    -e "s/server dns .*/server dns ${RESOLVER}/" \
    /etc/haproxy.conf

if [ $# -eq 0 ]; then
    exec /sbin/runsvdir -P /etc/service
fi

[ "$1" = '--' ] && shift
/sbin/runsvdir -P /etc/service
exec "$@"
