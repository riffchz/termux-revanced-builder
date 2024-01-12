#!/usr/bin/env bash
#
# Copyright riffchz
# Make date: 20240112
#


TOKEN="$1"
REPOSITORY="$2"
STATE=""
check() {
    assetsId=$(curl -s "https://api.github.com/repos/${REPOSITORY}/releases" -H "Authorization: token ${TOKEN}" | jq --raw-output '.[] | select(.tag_name=="patch").assets[] | select(.name | ascii_downcase | contains("json")).id')
    wget -q --auth-no-challenge --header="Accept:application/octet-stream" "https://${TOKEN}:@api.github.com/repos/${REPOSITORY}/releases/assets/$assetsId" -O patchesInfo.json

    json=$(cat patchesInfo.json | jq -rc ".[]")
    local forceUpdate=0
    for i in $json; do
        verLocal=$(echo $i | jq -r '.patchesVer')
        userLocal=$(echo $i | jq -r '.patchesUser')
        typeLocal=$(echo $i | jq -r '.patchesType')
        verServer=$(curl -s "https://api.github.com/repos/$userLocal/$typeLocal/releases/latest" | \
            jq  --raw-output '.assets[] | .browser_download_url | select(endswith("jar"))' | rev | cut -d/ -f2 | rev)
        if [[ ! "$verLocal" == "$verServer" ]]; then
            forceUpdate=1
        fi
    done
    [[ ${forceUpdate} -eq 1 ]] && { 
        STATE="Update"
        needUpdate
    } || { 
        STATE="No Update Found"
    }
}

needUpdate() {
    curl -X POST "https://api.github.com/repos/${REPOSITORY}/dispatches" \
        -H "Accept: application/vnd.github.everest-preview+json" \
        -H "Authorization: token ${TOKEN}" \
        -d "{\"event_type\": \"${STATE}\"}"
}

check