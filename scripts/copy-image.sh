#!/bin/bash

## Preflight check, exit if no match
if [[ $(getopt --version) != "getopt from util-linux 2.32"* ]]; then
        echo "Expected version \"getopt from util-linux 2.32.x\", got \"$(getopt --version)\" instead" >&2
        exit 2
fi

skopeo --version 2>/dev/null 1>/dev/null

if [[ $? != 0 ]]; then
        echo "Skopeo not found, please check your PATH environment" >&2
        exit 2
fi

version() {
        echo "copy-image.sh: 1.0"
        echo $(skopeo --version)
}

usage() {
        echo "copy-image.sh: [OPTIONS] -- PROTO:SOURCE PROTO:DESTINATION"
        echo "               --sync-namespace synchronize all images in the namespace SOURCE to DESTINATION"
        echo "                                (do not run this flag in public registry)"
        echo "               --sync-image     synchronize all tags in the repository"
        echo "               --authfile       specify pull secrets"
        echo "               --version        print script version"
        echo "               --help           print this help"
        echo
        echo "               PROTO is one of docker-archive: oci-archive: docker://, check skopeo man for more information"
        echo "               SOURCE is the repository name with the tag (ie. ubuntu:v1)"
        echo "               DESTINATION is one of: a directory, or a namespace"
}

_docker_setup_auth() {
        if [[ -n $AUTHFILE ]]; then
                local token=$(jq -r .auths.\"$1\".auth ${AUTHFILE})
                if [[ $token != "null" ]]; then
                        HEADERS="Authorization: Basic ${token}"
                        CURL_OPTS=-H
                fi
        fi
}

## strip url to get only domain
_docker_geturl() {
        local URL=${1}
        URL=${URL#*//}
        URL=${URL%%/*}
        echo ${URL}
}

## strip url to get only namespace or repository, works for both
_docker_getnamespace() {
        local NS=${1}
        NS=${NS#docker://}
        NS=${NS#*/}
        echo ${NS}
}

_docker_gettags() {
        local tags=$(curl ${CURL_OPTS} "${HEADERS}" -L -k https://$1/v2/$2/tags/list  2>&- | jq -r .tags[])
        curl ${CURL_OPTS} "${HEADERS}" -L -k https://$1/v2/$2/tags/list  2>&-
        for tag in $tags; do
                IMAGES+=($2:$tag)
        done
}

## get all images from registry catalog in namespace
_docker_getimages() {
## this 9999999 is just a gimmick to bypass pagination, this function should probably be avoided on public registry
        echo "Trying to get all image in the namespace $2 in $1"

        repositories=$(curl ${CURL_OPTS} "${HEADERS}" -L -k https://$1/v2/_catalog?n=9999999 2>&- | jq -r .repositories[] | grep $2)
        for repo in ${repositories}; do
                _docker_gettags $1 $repo;
        done
}

##this function only strips the proto
_dir_getnamespace() {
        echo ${1#*:}
}

##autofills the array with images, this function assumes that parameters is a directory
_dir_getimages_ns() {
        IMAGES=( $1/*:* )
}

##autofills the array with images, this assumes that parameters is a valid repository
_dir_getimages_repo() {
        IMAGES=( $1:* )
}

ARGS=$@
OPTS=$(getopt -u -lauthfile:,sync-image,sync-namespace,dest-namespace,version,help h,v ${ARGS})
SKOPEO_OPTS=
SYNC_NAMESPACE=0
SYNC_IMAGE=0
IMAGES=
CURL_OPTS=
HEADERS=

set -- ${OPTS}
while true; do
        case $1 in
                --authfile)
                        shift
                        SKOPEO_OPTS="--authfile ${1}"
                        AUTHFILE=${1}
                ;;
                --sync-namespace)
                        SYNC_NAMESPACE=1
                        SYNC_IMAGE=0
                ;;
                --sync-image)
                        SYNC_IMAGE=1
                        SYNC_NAMESPACE=0
                ;;
                --version|-v)
                        version;
                        exit 0;
                ;;
                --help|-h)
                        usage;
                        exit 0;
                ;;
                --)
                shift
                break;
        esac
        shift
done

SRC=${1}
DST=${2}

PROTO=
URL=

if [[ -z ${SRC} ]] || [[ -z ${DST} ]]; then
        usage;
        exit 2;
fi

## doing this before any internet requests
## sanitizing destination at least once
case ${DST%%:*} in
        docker)
                [[ $DST =~ docker:// ]];
        ;;
        docker-archive|oci-archive|dir|oci)
        ;;
        *)
                echo "Unsuported protocol ${DST%%:*}, please check skopeo man for more information" >&2
                exit 2;
        ;;
esac

## setup auth before going to registry
_docker_setup_auth $(_docker_geturl ${SRC});

if [[ $SYNC_NAMESPACE == 1 ]]; then
        case ${SRC%%:*} in
                docker)
                        PROTO="docker://"
                        URL=$(_docker_geturl ${SRC})
                        _docker_getimages ${URL} $(_docker_getnamespace ${SRC})
                        URL+=/
                ;;
                docker-archive|oci-archive|dir|oci)
                        PROTO=${SRC%%:*}:
                        _dir_getimages_ns ${URL}
                ;;
                *)
                        echo "Unsupported protocol ${SRC%%:*}, please check skopeo man for more information" >&2
                        exit 2;
                ;;
        esac
fi

if [[ $SYNC_IMAGE == 1 ]]; then
        case ${SRC%%:*} in
                docker)
                        PROTO="docker://"
                        URL=$(_docker_geturl ${SRC})
                        _docker_gettags ${URL} $(_docker_getnamespace ${SRC})
                        URL+=/
                ;;
                docker-archive|oci-archive|dir|oci)
                        PROTO=${SRC%%:*}:
                        _dir_getimages_repo $(_dir_getnamespace ${SRC})
                ;;
                *)
                        echo "Unsupported protocol ${SRC%%:*}, please check skopeo man for more information" >&2
                        exit 2;
                ;;
        esac
fi

## make it believe that there's a lot of image
if [[ $SYNC_NAMESPACE == 0 ]] && [[ $SYNC_IMAGE == 0 ]]; then
        case ${SRC%%:*} in
                docker)
                        PROTO="docker://"
                        URL=$(_docker_geturl ${SRC})/
                        IMAGES+=( ${SRC#docker://} )
                ;;
                docker-archive|oci-archive|dir|oci)
                        PROTO=${SRC%%:*}:
                        IMAGES+=( ${SRC#*:} )
                ;;
                *)
                        echo "Unsupported protocol ${SRC%%:*}, please check skopeo man for more information" >&2
                        exit 2;
                ;;
        esac
fi

for image in ${IMAGES[@]}; do
        srcimg=${PROTO}${URL}${image}
        dst=${DST}/${image}

        case ${dst%%:*} in
                docker-archive|oci-archive)
                        mkdir -p $(dirname ${dst#*:})
                        dst+=.tar.gz
                ;;
                oci|dir)
                        mkdir -p $(dirname ${dst#*:})
                ;;
        esac

        echo "Trying to copy ${srcimg} to ${dst}"
        skopeo copy $SKOPEO_OPTS --{dest,src}-tls-verify=false --all ${srcimg} ${dst}
        if [[ $? != 0 ]]; then
                echo "$(date -R): Failed to copy ${srcimg} to ${dst}" | tee /tmp/copy-error$(date +"%Y%m%d%H%M%S").log
                continue
        fi
        if [[ ${dst} =~ "-archive:" ]]; then
                filename=${dst%:*}
                mv ${filename#*:} ${dst#*:}
        fi
done
