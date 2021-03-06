#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

USAGE="usage: start-server.sh\n
    -d, --download-dir      : Directory where nzbget and transmission download to (Default: /media/external/Downloads)\n
    -c, --config-dir        : Directory to store all of the config information for all containers (Default: /media/external/Config)\n
    -m, --media-dir         : Directory where you store all your media (Default: /media/external/)\n
    -t, --plex-transcode-dir: Directory for plex to store its temporary transcode files (Default: /plex-transcode-tmp)\n
    --no-plex-claim         : Don't specify a plex claim token\n
"
print_usage_and_quit() {
    echo -e ${USAGE}
    exit 2;
}

download_dir=/media/external/Downloads
config_dir=/media/external/Config
media_dir=/media/external/
plex_transcode_dir=/plex-transcode-tmp
timezone=$(cat /etc/timezone)
ask_for_plex_claim=true

media_user_id=$(id -u media)
media_group_id=$(id -g media)

short=d:c:m:t:
long=download-dir:,config-dir:,media-dir:,plex-transcode-dir:,no-plex-claim

parsed=$(getopt --options ${short} --longoptions ${long} --name "$0" -- "$@") || print_usage_and_quit

eval set -- "$parsed"

while true; do
    case "$1" in
        -d|--download-dir)
            download_dir="$2"
            shift 2
            ;;
        -c|--config-dir)
            config_dir="$2"
            shift 2
            ;;
        -m|--media-dir)
            media_dir="$2"
            shift 2
            ;;
        -t|--plex-transcode-dir)
            plex_transcode_dir="$2"
            shift 2
            ;;
        --no-plex-claim)
            ask_for_plex_claim=false
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Something has gone seriously wrong"
            exit 3
            ;;
    esac
done

# Make the caddy and ddclient config dirs if necessary
# We need these to exist so we can drop the generated configs in there
mkdir -p ${config_dir}/caddy
mkdir -p ${config_dir}/ddclient

caddyfile=${config_dir}/caddy/Caddyfile
ddclient_conf=${config_dir}/ddclient/ddclient.conf
if [[ ! -f ${caddyfile} || ! -f ${ddclient_conf} ]]; then
    read -p "Enter your domain: " domain
fi

if [ ! -f ${caddyfile} ]; then
    read -p "Enter your admin email: " admin_email

    DOMAIN=${domain} ADMIN_EMAIL=${admin_email} envsubst < Caddyfile.tmpl > ${caddyfile}
fi

subdomains="ssh nzb torrent tv jackett movies request"
if [ ! -f ${ddclient_conf} ]; then
    read -p "Enter the dns host: " dns_host

    for subdomain in ${subdomains}; do
        read -p "Enter the dns username for the ${subdomain} subdomain: " username
        read -sp "Enter the dns password for the ${subdomain} subdomain:" password
        echo ""
        cat << EOF >> $ddclient_conf
protocol=dyndns2
use=web
server=${dns_host}
ssl=yes
login=${username}
password='${password}'
${subdomain}.${domain}

EOF
    done
fi

# You only want to ask for plex claim once, when you first start on this computer
# Afterwards, it will have stored credentials in the $config_dir/plex
if [[ "$ask_for_plex_claim" = true ]]; then
    read -p "Enter your Plex claim token: " plex_claim_token
    export PLEX_CLAIM_TOKEN=${plex_claim_token}
fi

cat > .env <<EOF
COMPOSE_PROJECT_NAME=server
DOWNLOAD_DIR=${download_dir}
CONFIG_DIR=${config_dir}
MEDIA_DIR=${media_dir}
PLEX_TRANSCODE_DIR=${plex_transcode_dir}
EOF

echo -e "PUID=${media_user_id}\nPGID=${media_group_id}\nTZ=${timezone}" > media.env
echo -e "PLEX_UID=${media_user_id}\nPLEX_GID=${media_group_id}\n" > plex.env

basic_auth=${config_dir}/caddy/basicauth.conf
if [ ! -f ${basic_auth} ]; then
    echo "Enter preferred admin auth credentials"
    read -p "Username: " username
    read -sp "Password: " password
    echo ""
    echo "basicauth / \"${username}\" \"${password}\"" > ${basic_auth}
fi

docker-compose up -d
