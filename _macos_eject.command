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
        -exec rm -rvf '{}' +
}


function disable_spotlight_indexing() {
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
    # drwxrwxrwx  1 nick  staff  -       131072 Apr 25 00:45 archive_box_off/
    # -rwxrwxrwx  1 nick  staff  arch         0 Apr 25 00:44 archive_box_off.txt*
    # drwxrwxrwx  1 nick  staff  -       131072 Apr 25 00:45 archive_box_on/
    # -rwxrwxrwx  1 nick  staff  -            0 Apr 25 00:44 archive_box_on.txt*

    # Info dump time: 
    #      In MacOS (at least in 10.15.3) there are multiple bugs in the ExFAT driver.
    #
    #      chflags arch/noarch on a directory behaves unexpectedly. Seeing arch does 
    #      not "stick" unless you set noarch first, at least on a freshly made directory.
    #      
    #      ls -lO, the only method to view the arch flag on macOS, does not display the
    #      presence or absence of the arch flag on directories. It works on files. This 
    #      creates another problem on macOS: chflags noarch <directory> does not work at 
    #      all on directories with the arch flag (silently) set. This seems to be because
    #      the filesystem is not able to properly read the presence of the arch flag on 
    #      a directory, and chflags sees no work to be done and exits. Therefore, and this
    #      is important: ONCE ARCH IS SET ON A DIRECTORY, IT IS IMPOSSIBLE TO REMOVE IN 
    #      MACOS WITHOUT DELETING IT AND RECREATING IT.
    #
    #      Therefore, it seems that the best way to guarantee setting the arch flag on
    #      a directory is to first call noarch, then call arch.
    #
    #      This was demonstrated by testing back-and-forth between macOS and Windows with
    #      the same filesystem.
    #
    #      The purpose of the archive bit in Windows was originally to mark a file as 
    #      being "ready to archive"; however this is the state of a file when the flag is
    #      _not_ set on the file itself. The flag indicates that the file has been successfully
    #      archived. But on Mac and Linux, ls -lO will show "arch" on files with the bit
    #      affirmatively set. This can lead to confusion between the two platforms as the
    #      bit seems "on" on Mac/Linux when it's "off" on Windows.
    #
    #      On HorizonOS (the Switch's operating system) it is possible to mark a directory
    #      as an "archive" using the archive bit. The directory then contains a series of 
    #      content files in the format %02d (00, 01, etc.). This is most likely due to the 4GB
    #      filesize limit on FAT32 and gives the OS the ability to split larger files up safely.
    #      The OS filesystem driver depends on the presence or absence of the archive bit to 
    #      find these files. A archive folder with the bit set incorrectly effectively does not
    #      exist in HorizonOS, and will lead to corruption errors or improper filesize info, etc.
    #      In the opposite case, an archive bit improperly set on a file will confuse the OS and
    #      the file may not be accessible.
    #
    #      Any file in HorizonOS can be configured as an archive and split up with this method.
    #      Therefore the safe way to set the archive bits is to look for the "00" file used as 
    #      the first chunk, and then set the bit on the immediate parent directory.
    #
    #      tl;dr: all files and folders should be "unchecked" on Windows, and show "arch" on MacOS
    #      and Linux ls -lO, with the exception of split archives which should be the inverse.
    #
    #      Hekate includes a tool to repair the archive bit. However this tool is clunky and will
    #      not cover instances of split archives outside of the Nintendo directory, or any split
    #      archive that doesn't have a .nca file extension. So, it sort of works. But this is better.

    # Guarantee everything on the SD card is +arch (UNCHECKED in Windows)
    sudo chflags -R noarch "${SD_CARD_PATH}"
    sudo chflags -R arch "${SD_CARD_PATH}"
    
    # Now all archive folders have the arch bit set; this is IMMUTABLE in MacOS now.
    # To unset the arch bit on the archive folders, they must be recreated.

    # Now remove the arch bit from all archive files (CHECKED in Windows)
    find "${SD_CARD_PATH}" \
         -type f \
         -name '00' \
         | while read -r line; do 
         
          archive_dir="$(dirname "${line}")"
          temp_archive="${archive_dir%.*}"
          mkdir "$temp_archive"
          mv "$archive_dir"/* "$temp_archive"/
          rmdir "$archive_dir"
          mv "$temp_archive" "$archive_dir"
        done
}


function eject_volume() {
    {
        sleep .1;
        diskutil umountDisk "${SD_CARD_PATH}";
    } &
}


function get_privileges() {
    sudo \
        --validate
}


function main() {
    get_privileges
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
