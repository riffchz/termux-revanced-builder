#!/usr/bin/env bash
#
# Copyright riffchz
# Make date: 20240112
#

HEADER="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0"
currentPath="$PWD"
tmpDir="$currentPath/tmp"
outputDir="$currentPath/output"
resourceDir="$currentPath/resources"
patchDir="$resourceDir/patches-tool"
apkDir="$resourceDir/base-apk"
config_file="$currentPath/config.yaml"
termuxApt="$patchDir/aapt2"

usage() {
    echo "Usage of $0:"
    echo 
    echo "$0 [options] application [arguments]"
    echo 
    echo "options:"
    echo "-h, --help             Show this help"
    echo "-e, --example          Print example usage command"
    echo
    echo "-f, --file             Specify your local APK file"
    echo "-b, --build            For specific your type build [ex: -b youtube]"
    echo "-r, --archi            Specific output for local apk builder"
    echo
    echo "--skip-patch           Skip revanced patches"
    echo "--clean                Clean up cache build after building"
    echo
    echo "-a, --auto-download    Auto downloading APK [ex: -a youtube]"
    echo -e "--apkmirror            Change auto download apk \n                       using website apkmirror, [default: apkcombo]"
    
    echo
    exit 1
}

example() {
    echo "Example usage of $0"
    echo
    echo "* Building online with auto download apk"
    echo "  $0 -a {idname} "
    echo
    echo "  You can use multiple flag"
    echo "  $0 -a {idname} -a {idname} -a {idname}"
    echo
    echo "* Building with local apk"
    echo "  $0 -f {apk-path} -b {idname} -r arm64-v8a"
    echo
    echo "- List supported idname"
    echo "  [youtube|youtube-music|instagram|twitch|twitter|reddit]"
    exit 1
}

log() { 
	echo -e "INFO: $*" | tee -a build.log
}

abort() {
    echo -e "FAIL: $*"
    exit 1
}

cleaner() {
    rm -rf "$tmpDir"
}

progressfilt () {
    local flag=false c cnt cr=$'\r' nl=$'\n'
    while IFS='' read -d '' -rn 1 c
    do
        if $flag; then
            printf '%s' "$c"
        else
            if [[ $c != $cr && $c != $nl ]]; then
                cnt=0
            else
                ((cnt++))
                if ((cnt > 1)); then
                    flag=true
                fi
            fi
        fi
    done
}

promptyn () {
    while true; do
        read -p "$1 " -n 1 -r
        echo
        case $REPLY in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

parseConfig() {
    idname=$(echo $1 | yq ".idname")
    moduleName=$(echo $1 | yq ".moduleName")
    packageName=$(echo $1 | yq ".packageName")
    outputType=$(echo $1 | yq ".outputType")
    integrations=$(echo $1 | yq ".integrations")
    patchOptions=$(echo $1 | yq ".patchOptions")
    patches=$(echo $1 | yq ".patches[]")
    hasRipLib=$(echo $1 | yq ".hasRipLib")
    exclusivePatches=$(echo $1 | yq ".exclusivePatches")
    archiConfig=$(echo $1 | yq ".archi[]")
    cliUser=$(echo $1 | yq ".cliRepo.user")
    cliRepo=$(echo $1 | yq ".cliRepo.repo")
    cliBranch=$(echo $1 | yq ".cliRepo.branch")
    patchesUser=$(echo $1 | yq ".patchesRepo.user")
    patchesRepo=$(echo $1 | yq ".patchesRepo.repo")
    patchesBranch=$(echo $1 | yq ".patchesRepo.branch")
    intergrationUser=$(echo $1 | yq ".intergrationRepo.user")
    intergrationRepo=$(echo $1 | yq ".intergrationRepo.repo")
    intergrationBranch=$(echo $1 | yq ".intergrationRepo.branch")   
    mkdir -p "$tmpDir/$idname"
}

checkDepencies() {
    log "Checking depencies..."
    local deps
    for name in jq java zip wget yq
    do
        if ! command -v $name &> /dev/null; then
            log "WARNING: [$name] needs to be installed. Use 'pkg install $name'"
            deps=1
        fi
    done
    if [[ "$(uname -o)" == "Android" ]]; then
        [[ "$(uname -m)" == "aarch64" ]] && {
            ARCHI_LINUX="arm64"
        } || {
            ARCHI_LINUX="arm"
        }
        [[ ! -f "${patchDir}/aapt2" ]] && {
            mkdir -p "$patchDir"
            log "Downloading termux aapt2"
            wget \
            -q --show-progress \
            --progress=bar:force \
            -O "${patchDir}/aapt2" \
            --header="$HEADER" \
            "https://github.com/rendiix/termux-aapt/raw/d7d4b4a344cc52b94bcdab3500be244151261d8e/prebuilt-binary/${ARCHI_LINUX}/aapt2" | progressfilt
        }
    fi
    [[ ${deps} -ne 1 ]] && log "Depencies passed... OK" || { 
        log "Install the above and rerun this script";exit 1;
    }
}

get_ver() {
    if [[ "$1" == "com.google.android.youtube" ]] || 
    [[ "$1" == "tv.twitch.android.app" ]] ||
    [[ "$1" == "com.instagram.android" ]]; then
        XVERSION=$(eval curl -s "https://api.revanced.app/v2/patches/latest" | \
                jq -rc "[.patches[] | select(.compatiblePackages[0].name==\"$1\" and \
                         .compatiblePackages[0].versions != null)] | first | .compatiblePackages[0].versions | last")
        if [[ "$APKMIRROR" == "false" ]]; then
            XVERSION="phone-$XVERSION-apk"
        fi
    else
 		local list_vers v versions=()
  		list_vers=$(req "https://www.apkmirror.com/uploads/?appcategory=$2" -)
		XVERSION=$(sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p' <<<"$list_vers")
		XVERSION=$(grep -iv "\(beta\|alpha\)" <<<"$XVERSION")
		for v in $XVERSION; do
			grep -iq "${v} \(beta\|alpha\)" <<<"$list_vers" || versions+=("$v")
		done
		XVERSION=$(head -1 <<<"$versions")
		if [[ "$APKMIRROR" == "false" ]]; then
            XVERSION="phone-apk"
        fi
    fi
}

_req() {
	if [ "$2" = - ]; then
		wget -q --show-progress --progress=bar:force -O "$2" --header="$3" "$1" | progressfilt
	else
		wget --timeout=5 --waitretry=0 --tries=3 --retry-connrefused -q --show-progress --progress=bar:force -O "$2" --header="$3" "$1" | progressfilt
	fi
}

req() {
	_req "$1" "$2" "$HEADER"
}

dl_apk() {
	local url=$1 regexp=$2 output=$3
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n "s/href=\"/@/g; s;.*${regexp}.*;\1;p")"
	url="https://www.apkmirror.com$(req "$url" - | grep "downloadButton" | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
   	url="https://www.apkmirror.com$(req "$url" - | grep "please click" | sed -n 's#.*href="\(.*key=[^"]*\)">.*#\1#;s#amp;##p')&forcebaseapk=true"
	req "$url" "$output"
}

apkmirrorDownload() {
	if [[ -z $4 ]]; then
		url_regexp='APK</span>[^@]*@\([^#]*\)'
	else
		case $4 in
			arm64-v8a) url_regexp='arm64-v8a'"[^@]*$6"''"[^@]*$5"'</div>[^@]*@\([^"]*\)' ;;
			armeabi-v7a) url_regexp='armeabi-v7a'"[^@]*$6"''"[^@]*$5"'</div>[^@]*@\([^"]*\)' ;;
			x86) url_regexp='x86'"[^@]*$6"''"[^@]*$5"'</div>[^@]*@\([^"]*\)' ;;
			x86_64) url_regexp='x86_64'"[^@]*$6"''"[^@]*$5"'</div>[^@]*@\([^"]*\)' ;;
			*) return 1 ;;
		esac 
	fi
	local base_apk="$1.apk"
	local dl_url=$(dl_apk "https://www.apkmirror.com/apk/$3-${XVERSION//./-}-release/" "$url_regexp" "$base_apk")
	if [ -z "$1.apk" ]; then
		abort "Cannot download $1"
		exit 1
	fi
}

apkcomboDownload() {
    local org=$1
    local pkgname=$2
    local archz=$3
    local id=$4
    get_ver ${pkgname}
    link=$(curl -s "https://apkcombo.com/${id}/${pkgname}/download/$XVERSION" | grep "${archz}" -A10 | \
        grep -oPm1 "(?<=href=\")https://download.apkcombo.com/.*?(?=\")")\&$(curl -s "https://apkcombo.com/checkin")
    wget --timeout=10 --waitretry=0 --tries=5 --retry-connrefused -q --show-progress --progress=bar:force -O "$apkDir/${org}.apk" --header="$HEADER" "$link" | progressfilt
}

getApkInfo() {
    if [[ "$(uname -o)" == "Android" ]]; then
        chmod +x $termuxApt
        outVersion=$(${termuxApt} dump badging "$1" | grep versionName | sed -e "s/.*versionName='//" -e "s/' .*//")
    else
        outVersion=$(aapt2 dump badging "$1" | grep versionName | sed -e "s/.*versionName='//" -e "s/' .*//")
    fi
    baseApk="$1"
}

downloadBins() {
    mkdir -p $patchDir
    mkdir -p $patchDir/$1
    local link urls size
    if [[ "$3" == "dev" ]]; then
        urls=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases)
        link=$(echo $urls | jq --raw-output --arg aa "$2" '.[0].assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
        name_patch_tool=$(echo $urls | jq --raw-output --arg aa "$2" '.[0].assets[] | select(.name | ascii_downcase | contains($aa)) | .name')
        size=$(echo $urls | jq --raw-output --arg aa "$2" '.[0].assets[] | select(.name | ascii_downcase | contains($aa)) | .size')
        patchesVer=$(echo $urls | jq --raw-output '.[0].assets[] | .browser_download_url | select(endswith("jar"))' | rev | cut -d/ -f2 | rev)
    else
        urls=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases/latest)
        link=$(echo $urls | jq --raw-output --arg aa "$2" '.assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
        name_patch_tool=$(echo $urls | jq --raw-output --arg aa "$2" '.assets[] | select(.name | ascii_downcase | contains($aa)) | .name')
        size=$(echo $urls | jq --raw-output --arg aa "$2" '.assets[] | select(.name | ascii_downcase | contains($aa)) | .size')
        patchesVer=$(echo $urls | jq --raw-output '.assets[] | .browser_download_url | select(endswith("jar"))' | rev | cut -d/ -f2 | rev)
    fi
    
    if [[ -f "$patchDir/$1/$name_patch_tool" ]]; then
        log "Checking version of $2"
        if [[ "$(cat $patchDir/$1/$name_patch_tool | wc -c)" == "$size" ]]; then
            log "$2 no update found"
        else
            log "Downloading $2 by [$1] branch of [$3]"
            wget --timeout=10 --waitretry=0 --tries=5 --retry-connrefused -q --show-progress --progress=bar:force "$link" -O "$patchDir/$1/$name_patch_tool" | progressfilt
        fi
    else
        log "Downloading $2 by [$1] branch of [$3]"
        wget --timeout=10 --waitretry=0 --tries=5 --retry-connrefused -q --show-progress --progress=bar:force "$link" -O "$patchDir/$1/$name_patch_tool" | progressfilt
    fi

    mkdir -p "$outputDir"
    local res
    [[ "$2" == *"revanced-patch"* ]] && {
        if [[ ! -f "$outputDir/patchesInfo.json" ]]; then
            jq -n ". + [{"patchesUser": \"$1\", "patchesType": \"$2\", "patchesVer": \"$patchesVer\"}]" > "$outputDir/patchesInfo.json"
        else
            local verz=$(cat "$outputDir/patchesInfo.json" | jq --raw-output ".[] | select(.patchesUser | ascii_downcase | contains(\"$1\")).patchesVer")
            if [[ ! "$patchesVer" == "$verz" ]]; then
                res=$(cat "$outputDir/patchesInfo.json" | jq --raw-output "map(del(select(.patchesUser | ascii_downcase | contains(\"$1\"))) | select(. != null)) |. + [{"patchesUser": \"$1\", "patchesType": \"$2\", "patchesVer": \"$patchesVer\"}]")
                echo "$res" > "$outputDir/patchesInfo.json"
            fi
        fi
    }
    
    [[ ! -f "$patchDir/$1/$name_patch_tool" ]] || [[ ! -s "$patchDir/$1/$name_patch_tool" ]] && {
         abort "No valid release of $2 was found!"
    }
}

buildMagisk() {
    local archi=$1
    mkdir -p "$tmpDir/magisk/META-INF/com/google/android"
    mkdir -p "$tmpDir/magisk/common"
    cp "$baseApk" "$tmpDir/magisk/common/original.apk"
    cp "$tmpDir/$idname/${idname}.apk" "$tmpDir/magisk/common/${idname}-${archi}.apk"
    echo "#MAGISK" > "$tmpDir/magisk/META-INF/com/google/android/updater-script"
    wget -q --show-progress --progress=bar:force "https://github.com/topjohnwu/Magisk/raw/master/scripts/module_installer.sh" -O "$tmpDir/magisk/META-INF/com/google/android/update-binary" | progressfilt
    {
        echo "id=$idname"
        echo "name=$moduleName"
        echo "version=v${outVersion}"
        echo "versionCode=$(echo $outVersion | sed 's/\.//g')"
        echo "author=ReVanced"
        echo "description=Continuing the legacy of Vanced"
    } > "$tmpDir/magisk/module.prop"
    {
        echo "#!/system/bin/sh"
        echo "[ \"\$BOOTMODE\" == \"false\" ] && abort \"Installation failed! ReVanced must be installed via Magisk Manager!\""
        echo "versionName=\$(dumpsys package $packageName | grep versionName | awk -F\"=\" '{print \$2}')"
        echo "[[ \"\$versionName\" != \"$outVersion\" ]] && pm install -r \$MODPATH/common/original.apk"
    } > "$tmpDir/magisk/customize.sh"
    {
        echo "#!/system/bin/sh"
        echo "stock_path=\$(pm path $packageName | grep base | sed 's/package://g')"
        echo "[ ! -z \$stock_path ] && umount -l \$stock_path"
    } > "$tmpDir/magisk/post-fs-data.sh"
    {
        echo "#!/system/bin/sh"
        echo "until [ \"\$(getprop sys.boot_completed)\" = 1 ]; do sleep 1; done"
        echo "until [ -d \"/sdcard/Android\" ]; do sleep 1; done"
        echo "MODPATH=\${0%/*}"
        echo "base_path=\$MODPATH/common/${idname}-${archi}.apk"
        echo "stock_path=\$(pm path $packageName | grep base | sed 's/package://g')"
        echo "if [ ! -z \$stock_path ]; then"
        echo "    mount -o bind \$base_path \$stock_path"
        echo "    chcon u:object_r:apk_data_file:s0 \$base_path"
        echo "fi"
    } > "$tmpDir/magisk/service.sh"
    log "Zipping module..."
    pushd "$tmpDir/magisk" >/dev/null
    nameZipp="${idname}-${archi}_v${outVersion}.zip"
    zip -qr "$tmpDir/$idname/$nameZipp" *
    popd >/dev/null
}

downloadingPatch() {
    downloadBins "$cliUser" "$cliRepo" "$cliBranch"
    downloadBins "$patchesUser" "$patchesRepo" "$patchesBranch"
    [[ "$integrations" == "true" ]] && {
        downloadBins "$intergrationUser" "$intergrationRepo" "$intergrationBranch"
    }
}

patchApk() {
    local archi=$1
    local typeBuild=$2
    mkdir -p "$tmpDir/$idname/tmp"
    echo "$patchOptions" > "$tmpDir/$idname/options.json"

    options=""
    while IFS= read -r patch; do
        options+=" -i \"$patch\""
    done <<< "$patchesx"

    [[ "$integrations" == "true" ]] && options+=" --merge $patchDir/$intergrationUser/revanced-integrations*.apk"
    local cmdArgs="java -jar $patchDir/$cliUser/revanced-cli*.jar patch \
              --patch-bundle $patchDir/$patchesUser/revanced-patch*.jar \
              --options $tmpDir/$idname/options.json $options \
              --out $tmpDir/$idname/${idname}.apk \
              --resource-cache $tmpDir/$idname/tmp \
              --force $baseApk"
    
    [[ "$exclusivePatches" == "true" ]] && {
        cmdArgs+=" --exclusive"
    }
    [[ $(uname -o) = Android ]] && {
        cmdArgs+=" --custom-aapt2-binary=${termuxApt}"
    }
    [[ "$hasRipLib" == "true" ]] && {
        cmdArgs+=" --rip-lib x86_64 --rip-lib x86"
        if [[ "$archi" == "arm64-v8a" ]]; then
            cmdArgs+=" --rip-lib armeabi-v7a"
        elif [[ "$archi" == "armeabi-v7a" ]]; then
            cmdArgs+=" --rip-lib arm64-v8a"
        fi
    }
    [[ "$CLEAN" == "true" ]] && {
        cmdArgs+=" --purge=true"
    }
    eval "$cmdArgs" | tee -a build.log
}

build() {
    local archi=$1
    local typeBuild=$2
    downloadingPatch
    [[ "$SKIP_PATCH" == "false" ]] && {
        log "Start patching $PATCH_NAME APK"
        patchApk "$archi" "$typeBuild"
    }
    mkdir -p "$outputDir"
    if [[ -f "$tmpDir/$idname/${idname}.apk" ]]; then
        if [[ "$typeBuild" == "apk" ]]; then
            mv -f "$tmpDir/$idname/${idname}.apk" "$tmpDir/$idname/NORoot-${idname}-${archi}_${outVersion}.apk"
            mv -f "$tmpDir/$idname/NORoot-${idname}-${archi}_${outVersion}.apk" "$outputDir/"
            [[ -f "$outputDir/NORoot-${idname}-${archi}_${outVersion}.apk" ]] && {
                log "Saved to: $outputDir/NORoot-${idname}-${archi}_${outVersion}.apk"
            } || abort "FIle not saved"
        elif [[ "$typeBuild" == "module" ]]; then
            log "Building Magisk module"
            buildMagisk "${archi}"
            log "Create module success"
            mv -f "$tmpDir/$idname/$nameZipp" "$outputDir/"
            [[ -f "$outputDir/$nameZipp" ]] && {
                log "Saved to: $outputDir/$nameZipp"
            } || abort "FIle not saved"
        fi
    else
        abort "Patching $PATCH_NAME failed!"
    fi
}

has_argument() {
    [[ ("$1" == *=* && -n ${1#*=}) || ( ! -z "$2" && "$2" != -*)  ]];
}

extract_argument() {
    echo "${2:-${1#*=}}"
}

APK_BASE=""
AUD_ARR=""
B_ARR=""
AARCH=""
SKIP_PATCH="false"
CLEAN="false"
AUD="false"
ARCH="false"
FLOCAL="false"
BUILD="false"
APKMIRROR="false"
handle_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help) usage;;
            -f | --file*)
                if ! has_argument $@; then
                    abort "File not specified." >&2
                fi
                APK_BASE=$(extract_argument $@)
                [[ ! -f "$APK_BASE" ]] && abort "File apk not found!"
                FLOCAL="true"
                shift
            ;;
            -b | --build*)
                if ! has_argument $@; then
                    abort "Need options for $@ [ ex: $@ youtube ]" >&2
                fi
                B_ARR="$(extract_argument $@)"
                BUILD="true"
                shift
            ;;
            -a | --auto-download*)
                if ! has_argument $@; then
                    abort "Need options for $@ [ ex: $@ youtube ]" >&2
                fi
                AUD_ARR+="$(extract_argument $@) "
                AUD="true"
                shift
            ;;
            -r | --archi*) 
                if ! has_argument $@; then
                    abort "Arch not specified." >&2
                fi
                AARCH="$(extract_argument $@)"
                ARCH="true"
                shift
            ;;
            -e | --example) example;;
            --apkmirror) APKMIRROR="true";;
            --skip-patch) SKIP_PATCH="true";;
            --clean) CLEAN="true";;
            *)
                echo "Invalid option: $1" >&2
                echo
                echo "Use -h, --help to see usage of $0"
                exit 1
            ;;
        esac
        shift
    done
}

starting() {
    log ""
    log "---------------------------------" 
    log "ReVanced Builder by riffchz"
    log "---------------------------------"
    log ""
    log "Starting"
}

handle_options "$@"
[[ "$AUD" == "true" ]] && [[ "$FLOCAL" == "true" ]] && abort "Cannot use auto download apk if (-f|--file) flag used"
[[ "$AUD" == "true" ]] && {
    [[ "$BUILD" == "true" ]] && abort "You cant use flag [ -b | --build ] if using flag [ -a | --auto-download ] or auto downloading APK"
    [[ "$ARCH" == "true" ]] && abort "You cant use flag [ -r | --archi ] if using flag [ -a | --auto-download ] or auto downloading APK"
    only_support=("twitch" "youtube" "youtube-music" "reddit" "twitter" "instagram")
    for i in ${AUD_ARR[@]}; do
        for x in ${only_support[@]}; do
            [[ "$i" == "$x" ]] && {
                [[ "$x" == "twitch" ]] && pkgN="tv.twitch.android.app" && grupN="twitch-interactive-inc"
                [[ "$x" == "youtube" ]] && pkgN="com.google.android.youtube" && grupN="google-inc"
                [[ "$x" == "youtube-music" ]] && pkgN="com.google.android.apps.youtube.music" && grupN="google-inc"
                [[ "$x" == "reddit" ]] && pkgN="com.reddit.frontpage" && grupN="redditinc"
                [[ "$x" == "twitter" ]] && pkgN="com.twitter.android" && grupN="x-corp"
                [[ "$x" == "instagram" ]] && pkgN="com.instagram.android" && grupN="instagram-instagram"
                pkgsn=".packageName==\"$pkgN\""
                touch build.log
                starting
                [[ -d "$tmpDir/magisk" ]] && rm -rf "$tmpDir/magisk" &> /dev/null
                checkDepencies
                mkdir -p "$apkDir"
                yq eval -oj $config_file | jq -rc ".[] | select($pkgsn)" | while read object; do
                    parseConfig "$object"
                    if [[ "$outputType" == "apk" ]]; then
                        build_mode=("apk")
                    elif [[ "$outputType" == "module" ]]; then
                        build_mode=("module")
                    else
                        build_mode=("apk" "module")
                    fi
                    while IFS= read -r aarch; do
                        for bmod in "${build_mode[@]}"; do
                            if [[ "$bmod" == "apk" ]]; then
                                if [[ "$patchesUser" == "revanced" ]]; then
                                    patchesx=$(echo "$object" | jq -rc '.patches -= ["GmsCore support"] | .patches += ["GmsCore support"] | .patches[]')
                                else
                                    patchesx=$(echo "$object" | jq -rc '.patches -= ["MicroG support"] | .patches += ["MicroG support"] | .patches[]')
                                fi
                            else
                                if [[ "$patchesUser" == "revanced" ]]; then
                                    patchesx=$(echo "$object" | jq -rc '.patches -= ["GmsCore support"] | .patches[]')
                                else
                                    patchesx=$(echo "$object" | jq -rc '.patches -= ["MicroG support"] | .patches[]')
                                fi
                            fi
                            [[ "$SKIP_PATCH" == "true" ]] && log "Skip patching APK is enable"
                            if [[ "$APKMIRROR" == "false" ]]; then
                                [[ ! -f "$apkDir/${x}-${aarch}.apk" ]] && {
                                    log "Downloading ${x}-${aarch}.apk"
                                    apkcomboDownload "${x}-${aarch}" "$pkgN" "${aarch}" "$x"
                                }
                            else
                                log "Getting APK version from server..."
                                if [[ "$x" == "instagram" ]]; then
                                    [[ ! -f "$apkDir/${x}-${aarch}.apk" ]] && {
                                        get_ver "$pkgN" "$grupN"
                                        log "Downloading ${x}-${aarch}.apk"
                                        apkmirrorDownload "$apkDir/${x}-${aarch}" "$grupN" "$x/$grupN/$grupN" "$aarch" "nodpi"
                                    }
                                elif [[ "$x" == "youtube-music" ]]; then
                                    [[ ! -f "$apkDir/${x}-${aarch}.apk" ]] && {
                                        get_ver "$pkgN" "$x"
                                        log "Downloading ${x}-${aarch}.apk"
                                        apkmirrorDownload "$apkDir/${x}-${aarch}" "$x" "$grupN/$x/$x" "$aarch"
                                    }
                                else
                                    [[ ! -f "$apkDir/${x}-${aarch}.apk" ]] && {
                                        get_ver "$pkgN" "$x"
                                        log "Downloading ${x}-${aarch}.apk"
                                        apkmirrorDownload "$apkDir/${x}-${aarch}" "$x" "$grupN/$x/$x"
                                    }
                                fi
                            fi
                            
                            PATCH_NAME="$x"                 
                            log "Get APK Info..."
                            getApkInfo "$apkDir/${x}-${aarch}.apk"
                            log "====[ ABOUT ]===="
                            log "PACKAGE: $pkgN"
                            log "VERSION: $outVersion"
                            log "BUILD TYPE: $bmod"
                            log "AARCH: $aarch"
                            log "OWNER: $patchesUser"
                            log "PATCHES: $patchesRepo"
                            log "================="
                            build "$aarch" "$bmod"
                            [[ -d "$tmpDir/magisk" ]] && rm -rf "$tmpDir/magisk" &> /dev/null
                            [[ "$CLEAN" == "true" ]] && {
                                log "Cleaning building cache...."
                                cleaner
                            }
                        done
                    done <<< "$archiConfig"
                done
            }
        done
    done
}

[[ "$FLOCAL" == "true" ]] && [[ ! "$BUILD" == "true" ]] && abort "If you using local apk you need passing argument (-b|--build) to specific your type build"
[[ "$FLOCAL" == "true" ]] && [[ "$BUILD" == "true" ]] && {
    [[ "$APKMIRROR" == "true" ]] && abort "You cant use flag --apkmirror if using local APK"
    [[ ! "$ARCH" == "true" ]] && abort "Need flag -r | --archi [ arm64-v8a|armeabi-v7a ] output"
    [[ "$B_ARR" == "twitch" ]] && pkgN="tv.twitch.android.app"
    [[ "$B_ARR" == "youtube" ]] && pkgN="com.google.android.youtube"
    [[ "$B_ARR" == "youtube-music" ]] && pkgN="com.google.android.apps.youtube.music"
    [[ "$B_ARR" == "reddit" ]] && pkgN="com.reddit.frontpage"
    [[ "$B_ARR" == "twitter" ]] && pkgN="com.twitter.android"
    [[ "$B_ARR" == "instagram" ]] && pkgN="com.instagram.android"
    touch build.log
    starting
    pkgsn=".packageName==\"$pkgN\""
    [[ -d "$tmpDir/magisk" ]] && rm -rf "$tmpDir/magisk" &> /dev/null
    checkDepencies
    mkdir -p "$apkDir"
    yq eval -oj $config_file | jq -rc ".[] | select($pkgsn)" | while read object; do
        parseConfig "$object"
        if [[ "$outputType" == "apk" ]]; then
            build_mode=("apk")
        elif [[ "$outputType" == "module" ]]; then
            build_mode=("module")
        else
            build_mode=("apk" "module")
        fi
        for bmod in "${build_mode[@]}"; do
            PATCH_NAME="$B_ARR"
            [[ "$SKIP_PATCH" == "true" ]] && log "Skip patching APK is enable"
            log "Get APK Info..."
            getApkInfo "$APK_BASE"
            log "====[ ABOUT ]===="
            log "PACKAGE: $pkgN"
            log "VERSION: $outVersion"
            log "BUILD TYPE: $bmod"
            log "AARCH: $aarch"
            log "OWNER: $patchesUser"
            log "PATCHES: $patchesRepo"
            log "================="
            build "$AARCH" "$bmod"
            [[ -d "$tmpDir/magisk" ]] && rm -rf "$tmpDir/magisk" &> /dev/null
            [[ "$CLEAN" == "true" ]] && {
                log "Cleaning building cache...."
                cleaner
            }
        done
    done
}
