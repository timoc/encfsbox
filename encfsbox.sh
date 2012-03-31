#!/bin/bash
# parse command line
CMD=$1
# exit if using an ininitialised variable
set -o nounset
# exit if command returns error state - stop snowballing
# set -o errexit
BOX_DEFAULT_COMMAND=dropbox.py
MNT_SEARCH_DEFAULT="${HOME}/.dropbox_enc/Dropbox"
MNT_SEARCH="${DROPBOX_DIR:=${MNT_SEARCH_DEFAULT}}"
# no error message needed
declare _USAGE="" _SILENTLY="" _BOX="status" _CMD=""

if [ -e "${MNT_SEARCH}" ] ; then 
    case "${CMD}" in
        m|mount)
            _CMD="mount"
#            _BOX="idle"
            ;;
        u|umount)
            _CMD="umount"
#            _BOX="idle"
            ;;
        r|refresh)
            _SILENTLY="y"
            _BOX="restart"
            _CMD="mount"
            ;;
        c|conflicts)
            _CMD="conflicts"
            _BOX="idle"
            ;;
        *)
            _USAGE="Y"
            ;;
    esac
    # create LOCKFILE see examples.org
    LOCKFILE=~/tmp/mnt+enc+dropbox.lock
    if ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null;
    then
        trap 'rm -f "$LOCKFILE"; stty sane ; exit $?' INT TERM EXIT

        case "${_BOX}" in 
            restart)
                if [[ "Dropbox isn't running!" == $(${BOX_DEFAULT_COMMAND} status) ]] ; then
                    ${BOX_DEFAULT_COMMAND} start
                fi
                ;;
            idle)
                if [[ "Idle" != $(${BOX_DEFAULT_COMMAND} status) ]] ; then
                    echo "!!!!! Cannot resolve conflicts until Dropbox is Idle !!!!!"
                    exit 1
                fi
                ;;
            status|*)
                echo "Dropbox Status:$(${BOX_DEFAULT_COMMAND} status)"
                ;;
        esac

        for ENCFS in $(ls -d ${MNT_SEARCH}/enc_*) ; do
            MNT_NAME=$(basename ${ENCFS})
            MNT_NAME="${HOME}/${MNT_NAME/enc_/}"
            MNTED=$(mount | grep "${MNT_NAME}")
            FOUND_CONFLICTED="$(find ${ENCFS} -name "*conflict*" -exec sh -c 'if true; then ls -l "$1"; fi' -- {} \;)"
            case "${_CMD}" in
                mount)
                    if [[ ! -z "${FOUND_CONFLICTED}" ]] ; then
                        echo "!! Conflicted Files found in ${ENCFS} !!"
                    fi
                    if [[ "${MNTED}" == "" ]] ; then 
                        if [[ ! -e "${ENCFS}/.encfs6.xml" ]] ; then 
                            echo "~~ use AES 256, block 1024, defaults"
                        fi
                        echo "== ${MNT_NAME} (${ENCFS}) "
                        encfs ${ENCFS} ${MNT_NAME}
                        MNTED=$(mount | grep "${MNT_NAME}")
                        if [ -z $_SILENTLY ] ; then
                            echo "++ ${MNTED}"
                        fi
                    fi
                    ;;
                umount)
                    if [[ "${MNTED}" != "" ]] ; then 
                        fusermount -u ${MNT_NAME}
                        MNTED=$(mount | grep "${MNT_NAME}")
                        echo "-- unmounted"
                    fi
                    ;;
                conflicts)
                    if [[ ! -z "${FOUND_CONFLICTED}" ]] ; then
                        echo "!!!!!!!!!!!!! Resolving Conflicts !!!!!!!!!!!!"
                        echo "== Resolving for ${MNT_NAME} (${ENCFS}) "
                        echo "++ Enter Password:"
                        read -s MNT_PASSWD
                        stty sane

                        find ${ENCFS} -name "*conflicted*" -print0 | while read -d $'\0' CONFLICTED
                        do
                            ORIGINAL=$(expr match "${CONFLICTED}" '\([^\(]*\) (.*conflicted copy.*)[^\)]*')
                            CONFLICT=$(expr match "${CONFLICTED}" '[^\(]* (\(.*conflicted copy.*\))[^\)]*')
                            DECODED=$(encfsctl decode --extpass="echo ${MNT_PASSWD}" ${ENCFS} "${ORIGINAL}")
                            NEWNAME="${DECODED} (${CONFLICT})"
                            ENCODED=$(encfsctl encode --extpass="echo ${MNT_PASSWD}" ${ENCFS} "${NEWNAME}")

                            echo "+++++++++"
                            echo "--:${DECODED}"
                            echo "->:${NEWNAME}"
#                            echo "--:${CONFLICTED}"
#                            echo "->:${ENCODED}"
                            mv -iv "${CONFLICTED}" "${ENCFS}/${ENCODED}"
                        done
                        echo "================================"
                    fi
                    ;;

                *)
                    echo "================================"
                    echo "== ${MNT_NAME} (${ENCFS}) "
                    if [[ "${MNTED}" == "" ]] ; then 
                        if [[ ! -e "${ENCFS}/.encfs6.xml" ]] ; then 
                            echo "~~ uncreated"
                        else
                            echo "-- unmounted"
                        fi
                    else
                        echo "++ ${MNTED}"
                    fi
                    if [[ ! -z "${FOUND_CONFLICTED}" ]] ; then
                        echo "!! Conflicted Files found in ${ENCFS} !!"
                        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
                        echo "${FOUND_CONFLICTED}"
                    fi
                    echo "================================"
                    ;;
            esac


        done;
        # clean up LOCKFILE
        rm -f "$LOCKFILE"
        trap - INT TERM EXIT
    else
        if [ -z $_SILENTLY ] ; then
            echo "Failed to acquire LOCKFILE: $LOCKFILE. Held by $(cat $LOCKFILE)"
#        else
#            echo "$(cat $LOCKFILE)"
        fi
    fi 
else
    echo "!! dropbox directory does not exist !!"
    echo \$DROPBOX_DIR=${MNT_SEARCH}
    _USAGE=y
fi

if [ ! -z $_USAGE} ] ; then
    echo <<EOF 
usage: $0 <status|mount|umount|refresh>

mount/unmount dropbox encfs filesystems. this script lokos in the
dropbox for directories prefixed with enc_<dirname> and mounts the
encfs filesystems as ~/<dirname>. if enc_<dirname> is not an encfs
filesystem it will initialise an encfs filesystem in that directory.

It defaults to searching ${MNT_SEARCH_DEFAULT}, but this can be
changed by using the DROPBOX_DIR environmental variable. You can set
it in your bashrc or set it like this:

DROPBOX_DIR=~/Dropbox $0 mount

Commands:
status - display status of encfs mounts
mount - mount/create encfs filesystems
umount - unmount encfs filesystems
refresh - silently check status and mount/create encfs filesystems if unmounted.

EOF
fi
