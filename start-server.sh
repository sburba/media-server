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

parsed=$(getopt --options ${short} --longoptions $long --name "$0" -- "$@") || print_usage_and_quit

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

if [[ "$ask_for_plex_claim" = true ]]; then
    read -p "Enter your Plex claim token: " plex_claim_token
    export PLEX_CLAIM_TOKEN=${plex_claim_token}
fi

export DOWNLOAD_DIR=${download_dir}
export CONFIG_DIR=${config_dir}
export MEDIA_DIR=${media_dir}
export PLEX_TRANSCODE_DIR=${plex_transcode_dir}

echo -e "PUID=${media_user_id}\nPGID=${media_group_id}\nTZ=${timezone}" > media.env
echo -e "PLEX_UID=${media_user_id}\nPLEX_GID=${media_group_id}\n" > plex.env

if [ ! -f ./basicauth.conf ]; then
    echo "Enter preferred admin auth credentials"
    read -p "Username: " username
    read -sp "Password: " password
    echo ""
    echo "basicauth / \"${username}\" \"${password}\"" > basicauth.conf
fi

docker-compose -p server up -d
rm media.env
rm plex.env
