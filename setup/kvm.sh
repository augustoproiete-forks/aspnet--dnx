# kvm.sh
# Source this file from your .bash-profile or script to use
_kvm_has() {
    type "$1" > /dev/null 2>&1
    return $?
}

if _kvm_has "unsetopt"; then
    unsetopt nomatch 2>/dev/null
fi

if [ -z "$KRE_USER_HOME" ]; then
    eval KRE_USER_HOME=~/.kre
fi

KRE_USER_PACKAGES="$KRE_USER_HOME/packages"
KRE_MONO45=
KRE_X86=
KRE_X64=
KRE_NUGET_API_URL="https://www.myget.org/F/aspnetvnext/api/v2"

_kvm_find_latest() {
    local platform="mono45"
    local architecture="x86"

    if ! _kvm_has "curl"; then
        echo 'KVM Needs curl to proceed.' >&2;
        return 1
    fi

    local url="$KRE_NUGET_API_URL/GetUpdates()?packageIds=%27KRE-$platform-$architecture%27&versions=%270.0%27&includePrerelease=true&includeAllVersions=false"
    local cmd=
    local xml="$(curl $url 2>/dev/null)"
    version="$(echo $xml | sed 's/.*<[a-zA-Z]:Version>\([^<]*\).*/\1/')"
    [[ $xml == $version ]] && return 1
    echo $version
}

_kvm_strip_path() {
    echo "$1" | sed -e "s#$KRE_USER_PACKAGES/[^/]*$2[^:]*:##g" -e "s#:$KRE_USER_PACKAGES/[^/]*$2[^:]*##g" -e "s#$KRE_USER_PACKAGES/[^/]*$2[^:]*##g"
}

_kvm_prepend_path() {
    if [ -z "$1" ]; then
        echo "$2"
    else
        echo "$2:$1"
    fi
}

_kvm_package_version() {
    local kreFullName="$1"
    echo "$kreFullName" | sed "s/[^.]*.\(.*\)/\1/"
}

_kvm_package_name() {
    local kreFullName="$1"
    echo "$kreFullName" | sed "s/\([^.]*\).*/\1/"
}

_kvm_package_runtime() {
    local kreFullName="$1"
    echo "$kreFullName" | sed "s/KRE-\([^-]*\).*/\1/"
}

_kvm_download() {
    local kreFullName="$1"
    local kreFolder="$2"

    local pkgName=$(_kvm_package_name "$kreFullName")
    local pkgVersion=$(_kvm_package_version "$kreFullName")
    local url="$KRE_NUGET_API_URL/package/$pkgName/$pkgVersion"
    local kreFile="$kreFolder/$kreFullName.nupkg"

    if [ -e "$kreFolder" ]; then
        echo "$kreFullName already installed."
        return 0
    fi

    echo "Downloading $kreFullName from $KRE_NUGET_API_URL"

    if ! _kvm_has "curl"; then
        echo "KVM Needs curl to proceed." >&2;
        return 1
    fi

    mkdir -p "$kreFolder" > /dev/null 2>&1

    local httpResult=$(curl -L -D - -u aspnetreadonly:4d8a2d9c-7b80-4162-9978-47e918c9658c "$url" -o "$kreFile" 2>/dev/null | grep "^HTTP/1.1" | head -n 1 | sed "s/HTTP.1.1 \([0-9]*\).*/\1/")

    [[ $httpResult == "404" ]] && echo "$kreFullName was not found in repository $KRE_NUGET_API_URL" && return 1
    [[ $httpResult != "302" && $httpResult != "200" ]] && echo "HTTP Error $httpResult fetching $kreFullName from $KRE_NUGET_API_URL" && return 1

    _kvm_unpack $kreFile $kreFolder
}

_kvm_unpack() {
    local kreFile="$1"
    local kreFolder="$2"

    echo "Installing to $kreFolder"

    if ! _kvm_has "unzip"; then
        echo "KVM Needs unzip to proceed." >&2;
        return 1
    fi

    unzip $kreFile -d $kreFolder > /dev/null 2>&1

    [ -e "$kreFolder/[Content_Types].xml" ] && rm "$kreFolder/[Content_Types].xml"

    [ -e "$kreFolder/_rels/" ] && rm -rf "$kreFolder/_rels/"

    [ -e "$kreFolder/package/" ] && rm -rf "$kreFolder/_package/"

    #Set shell commands as executable
    find "$kreFolder/bin/" -type f \
        -exec sh -c "head -c 11 {} | grep '/bin/bash' > /dev/null"  \; -print | xargs chmod 775
}

# This is not currently required. Placeholder for the case when we have multiple platforms  (ie if we bundle mono)
_kvm_requested_platform() {
    local default=$1
    [[ -z $KRE_MONO45 ]] && echo "mono45" && return
    echo $default
}

# This is not currently required. Placeholder for the case where we have multiple architectures (ie if we bundle mono)
_kvm_requested_architecture() {
    local default=$1

    [[ -n $KRE_X86 && -n $KRE_X64 ]] && echo "This command cannot accept both -x86 and -x64" && return 1
    [[ -z $KRE_X86 ]] && echo "x86" && return
    [[ -z $KRE_X64 ]] && echo "x64" && return
    echo $default
}

_kvm_requested_version_or_alias() {
    local versionOrAlias="$1"

    if [ -e "$KRE_USER_HOME/alias/$versionOrAlias.alias" ]; then
        local kreFullName=$(cat "$KRE_USER_HOME/alias/$versionOrAlias.alias")
        local pkgName=$(echo $kreFullName | sed "s/\([^.]*\).*/\1/")
        local pkgVersion=$(echo $kreFullName | sed "s/[^.]*.\(.*\)/\1/")
        local pkgPlatform=$(_kvm_requested_platform $(echo "$pkgName" | sed "s/KRE-\([^-]*\).*/\1/"))
        local pkgArchitecture=$(_kvm_requested_architecture $(echo "$pkgName" | sed "s/.*-.*-\([^-]*\).*/\1/"))
    else
        local pkgVersion=$versionOrAlias
        local pkgPlatform=$(_kvm_requested_platform "mono45")
        local pkgArchitecture=$(_kvm_requested_architecture "x86")
    fi
    echo "KRE-$pkgPlatform-$pkgArchitecture.$pkgVersion"
}

# This will be more relevant if we support global installs
_kvm_locate_kre_bin_from_full_name() {
    local kreFullName=$1
    [ -e "$KRE_USER_PACKAGES/$kreFullName/bin" ] && echo "$KRE_USER_PACKAGES/$kreFullName/bin" && return
}

kvm()
{
    if [ $# -lt 1 ]; then
        kvm help
        return
    fi

    case $1 in
        "help" )
            echo ""
            echo "K Runtime Environment Version Manager - Build {{BUILD_NUMBER}}"
            echo ""
            echo "USAGE: kvm <command> [options]"
            echo ""
            echo "kvm upgrade"
            echo "install latest KRE from feed"
            echo "add KRE bin to path of current command line"
            echo "set installed version as default"
            echo ""
            echo "kvm install <semver>|<alias>|<nupkg>|latest [-a|-alias <alias>] [-p -persistent]"
            echo "<semver>|<alias>  install requested KRE from feed"
            echo "<nupkg>           install requested KRE from local package on filesystem"
            echo "latest            install latest version of KRE from feed"
            echo "-a|-alias <alias> set alias <alias> for requested KRE on install"
            echo "-p -persistent    set installed version as default"
            echo "add KRE bin to path of current command line"
            echo ""
            echo "kvm use <semver>|<alias>|none [-p -persistent]"
            echo "<semver>|<alias>  add KRE bin to path of current command line   "
            echo "none              remove KRE bin from path of current command line"
            echo "-p -persistent   set selected version as default"
            echo ""
            echo "kvm list"
            echo "list KRE versions installed "
            echo ""
            echo "kvm alias"
            echo "list KRE aliases which have been defined"
            echo ""
            echo "kvm alias <alias>"
            echo "display value of named alias"
            echo ""
            echo "kvm alias <alias> <semver>"
            echo "set alias to specific version"
            echo ""
            echo ""
        ;;

        "upgrade" )
            [ $# -ne 1 ] && kvm help && return
            kvm install latest -p
        ;;

        "install" )
            [ $# -lt 2 ] && kvm help && return
            shift
            local persistant=
            local versionOrAlias=
            local alias=
            while [ $# -ne 0 ]
            do
                if [[ $1 == "-p" || $1 == "-persistant" ]]; then
                    local persistent="-p"
                elif [[ $1 == "-a" || $1 == "-alias" ]]; then
                    local alias=$2
                    shift
                elif [[ -n $1 ]]; then
                    [[ -n $versionOrAlias ]] && echo "Invalid option $1" && kvm help && return
                    local versionOrAlias=$1
                fi
                shift
            done
            if [[ "$versionOrAlias" == "latest" ]]; then
                echo "Determining latest version"
                local versionOrAlias=$(_kvm_find_latest mono45 x86)
                echo "Latest version is $versionOrAlias"
            fi
            if [[ "$versionOrAlias" == *.nupkg ]]; then
                local kreFullName=$(basename $versionOrAlias | sed "s/\(.*\)\.nupkg/\1/")
                local kreVersion=$(_kvm_package_version "$kreFullName")
                local kreFolder="$KRE_USER_PACKAGES/$kreFullName"
                local kreFile="$kreFolder/$kreFullName.nupkg"

                if [ -e "$kreFolder" ]; then
                  echo "$kreFullName already installed"
                else
                  mkdir "$kreFolder" > /dev/null 2>&1
                  cp -a "$versionOrAlias" "$kreFile"
                  _kvm_unpack "$kreFile" "$kreFolder"
                fi
                kvm use "$kreVersion" "$persistent"
                [[ -n $alias ]] && kvm alias "$alias" "$kreVersion"
            else
                local kreFullName="$(_kvm_requested_version_or_alias $versionOrAlias)"
                local kreFolder="$KRE_USER_PACKAGES/$kreFullName"
                _kvm_download "$kreFullName" "$kreFolder"
                [[ $? == 1 ]] && return
                kvm use "$versionOrAlias" "$persistent"
                [[ -n $alias ]] && kvm alias "$alias" "$versionOrAlias"
            fi
        ;;

        "use" )
            [ $# -gt 3 ] && kvm help && return
            [ $# -lt 2 ] && kvm help && return

            shift
            local persistent=
            while [ $# -ne 0 ]
            do
                if [[ $1 == "-p" || $1 == "-persistent" ]]; then
                    local persistent="true"
                elif [[ -n $1 ]]; then
                    local versionOrAlias=$1
                fi
                shift
            done

            if [[ $versionOrAlias == "none" ]]; then
                echo "Removing KRE from process PATH"
                # Strip other version from PATH
                PATH=$(_kvm_strip_path "$PATH" "/bin")

                if [[ -n $persistent && -e "$KRE_USER_HOME/alias/default.alias" ]]; then
                    echo "Setting default KRE to none"
                    rm "$KRE_USER_HOME/alias/default.alias"
                fi
                return 0
            fi

            local kreFullName=$(_kvm_requested_version_or_alias "$versionOrAlias")
            local kreBin=$(_kvm_locate_kre_bin_from_full_name "$kreFullName")

            if [[ -z $kreBin ]]; then
                echo "Cannot find $kreFullName, do you need to run 'kvm install $versionOrAlias'?"
                return 1
            fi

            echo "Adding" $kreBin "to process PATH"

            PATH=$(_kvm_strip_path "$PATH" "/bin")
            PATH=$(_kvm_prepend_path "$PATH" "$kreBin")

            if [[ -n $persistent ]]; then
                local kreVersion=$(_kvm_package_version "$kreFullName")
                kvm alias default "$kreVersion"
            fi
        ;;

        "alias" )
            [[ $# -gt 3 ]] && kvm help && return

            [[ ! -e "$KRE_USER_HOME/alias/" ]] && mkdir "$KRE_USER_HOME/alias/" > /dev/null

            if [[ $# == 1 ]]; then
                echo ""
                local format="%-20s %s\n"
                printf "$format" "Alias" "Name"
                printf "$format" "-----" "----"
                for _kvm_file in $(find "$KRE_USER_HOME/alias" -name *.alias); do
                    local alias="$(basename $_kvm_file | sed 's/.alias//')"
                    local name="$(cat $_kvm_file)"
                    printf "$format" "$alias" "$name"
                done
                echo ""
                return
            fi

            local name="$2"

            if [[ $# == 2 ]]; then
                [[ ! -e "$KRE_USER_HOME/alias/$name.alias" ]] && echo "There is no alias called '$name'" && return
                cat "$KRE_USER_HOME/alias/$name.alias"
                echo ""
                return
            fi

            local semver="$3"
            local kreFullName="KRE-$(_kvm_requested_platform mono45)-$(_kvm_requested_architecture x86).$semver"

            [[ ! -d "$KRE_USER_PACKAGES/$kreFullName" ]] && echo "$semver is not an installed KRE version." && return 1

            echo "Setting alias '$name' to '$kreFullName'"

            echo "$kreFullName" > "$KRE_USER_HOME/alias/$name.alias"
        ;;

        "list" )
            [[ $# -gt 2 ]] && kvm help && return

            [[ ! -d $KRE_USER_PACKAGES ]] && echo "KRE is not installed." && return 1

            local searchGlob="KRE-*"
            if [ $# == 2 ]; then
                local versionOrAlias=$2
                local searchGlob=$(_kvm_requested_version_or_alias "$versionOrAlias")
            fi
            echo ""
            local formatString="%-6s %-20s %-7s %-12s %s\n"
            printf "$formatString" "Active" "Version" "Runtime" "Architecture" "Location"
            printf "$formatString" "------" "-------" "-------" "------------" "--------"
            for f in $(find $KRE_USER_PACKAGES/* -name "$searchGlob" -type d -prune -exec basename {} \;); do
                local active=""
                [[ $PATH == *"$KRE_USER_PACKAGES/$f/bin"* ]] && local active="  *"
                local pkgName=$(_kvm_package_runtime "$f")
                local pkgVersion=$(_kvm_package_version "$f")
                printf "$formatString" "$active" "$pkgVersion" "$pkgName" "x86" "$KRE_USER_PACKAGES"
                [[ $# == 2 ]] && echo "" &&  return 0
            done

            echo ""
            [[ $# == 2 ]] && echo "$versionOrAlias not found" && return 1
        ;;

        *)
            echo "Unknown command $1"
            return 1
    esac
}

kvm list default >/dev/null && kvm use default >/dev/null || true
