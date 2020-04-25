#!/bin/bash

function prompt() {
    local message="$1"
    local response

    while [[ -z "${response}" ]]; do
        read -rp "${message} [y/n] " response
        
        if [[ "${response}" =~ ^[yY]$ ]]; then
            return 0
        elif [[ "${response}" =~ ^[nN]$ ]]; then
            return 1
        else
            unset response
        fi
    done
}


function exit_with_error() {
    echo "${0##*/}: $@" >&2
    exit 1
}


function select_sd_card_volume() {
    if [[ -n "${SD_CARD_PATH}" ]]; then
        echo "Selected ${SD_CARD_PATH}"
        return
    fi

    local pattern='on\ (\/Volumes\/.*)\ \('
    local volumes=()

    while read -r line; do
        if [[ "${line}" =~ ${pattern} ]]; then
            volumes+=("${BASH_REMATCH[1]}")
        fi
    done < <(mount | grep -F 'on /Volumes' | grep -E '\((msdos|exfat),')

    if [[ "${#volumes[@]}" -eq 0 ]]; then
        exit_with_error "No FAT/exFAT volumes mounted"
    elif [[ "${#volumes[@]}" -eq 1 ]]; then
        export SD_CARD_PATH=${volumes[0]}
    else
        echo "Multiple FAT/exFAT volumes mounted"
        for volume in "${volumes[@]}"; do
            prompt "Do you want to use ${volume}?" \
                && export SD_CARD_PATH="${volume}" \
                && break
        done

        if [[ -z "${SD_CARD_PATH}" ]]; then
            exit_with_error "You must select at least one volume to continue"
        fi
    fi

    echo "Selected ${SD_CARD_PATH}"
}


function delete_macos_metadata() {
    # https://github.com/github/gitignore/blob/master/Global/macOS.gitignore
    sudo find "${SD_CARD_PATH}" \
        -type f \
        \( \
            -name '.DS_Store' \
            -o \
            -name '.AppleDouble' \
            -o \
            -name '.LSOverride' \
            -o \
            -name '.Trashes' \
            -o \
            -name '.fseventsd' \
            -o \
            -name '.Spotlight-V*' \
            -o \
            -name '._*' \
        \) \
        -exec rm -rvf {} +
}


function disable_spotlight_indexing() {
    mdutil -i off "${SD_CARD_PATH}"
    touch "${SD_CARD_PATH}/.metadata_never_index"
}


function disable_trashes() {
    touch "${SD_CARD_PATH}/.Trashes"
}


function disable_fseventsd() {
    mkdir -p "${SD_CARD_PATH}/.fseventsd"
    touch "${SD_CARD_PATH}/.fseventsd/no_log" 
}


function fix_archive_bits() {
    # https://gbatemp.net/threads/how-to-fix-archive-bit-for-all-sd-files-and-folders.515258/
    # View these attributes with: `ls -lO`
    sudo chflags -R arch "${SD_CARD_PATH}"
    sudo chflags -R noarch "${SD_CARD_PATH}"/Nintendo
}


function eject_volume() {
    diskutil umountDisk force "${SD_CARD_PATH}"
}


function main() {
    select_sd_card_volume
    disable_spotlight_indexing
    delete_macos_metadata
    disable_trashes
    disable_fseventsd
    fix_archive_bits
    eject_volume
}

# optional: define a static SD_CARD_PATH to prevent hunting
#export SD_CARD_PATH="/Volumes/Switch"
main "$@"
