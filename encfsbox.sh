#!/bin/bash
#
# Copyright (c) 2012 Tim O'Callaghan 2012
#
# LICENSE: (The MIT License)
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the ‘Software’), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# parse command line args
CMD=$1
# set bash to exit if using an ininitialised variable
set -o nounset
# set exit if command returns error state - stop snowballing
# set -o errexit

# script defaults
# dropbox helper
BOX_DEFAULT_COMMAND=dropbox.py
BOX_COMMAND="${DROPBOX_COMMAND:=${BOX_DEFAULT_COMMAND}}"
# default dropbox directory
MNT_SEARCH_DEFAULT="${HOME}/.dropbox_enc/Dropbox"
# check dropbox is not set in environment
MNT_SEARCH="${DROPBOX_DIR:=${MNT_SEARCH_DEFAULT}}"

# initialise shell variables
# if non empty then show script usage
_USAGE=""
# if non empty be as silent as possible - for login script
_SILENTLY=""
# 'dropbox' command to perform.
 _BOX="status"
# encfs operation to perform.
_CMD=""

# parse command
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

    # create lockfile and catch script exit to remove it properly.
    LOCKFILE=~/tmp/mnt+enc+dropbox.lock
    if ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null;
    then
        trap 'rm -f "$LOCKFILE"; stty sane ; exit $?' INT TERM EXIT

        # perform dropbox deamon managment/status checking, if command exists
        if [[ "${BOX_COMMAND}" != "true" ]] ; then 
            case "${_BOX}" in 
                restart)
                    if [[ "Dropbox isn't running!" == $(${BOX_COMMAND} status) ]] ; then
                        ${BOX_COMMAND} start
                    fi
                    ;;
                idle)
                    if [[ "Idle" != $(${BOX_COMMAND} status) ]] ; then
                        echo "!!!!! Cannot resolve conflicts until Dropbox is Idle !!!!!"
                        exit 1
                    fi
                    ;;
                status|*)
                    echo "Dropbox Status:$(${BOX_COMMAND} status)"
                    ;;
            esac
        fi

        # iterate through all enc_ directories in the root of the dropbox path
        for ENCFS in $(ls -d ${MNT_SEARCH}/enc_*) ; do
            # caclulate mount names
            MNT_NAME=$(basename ${ENCFS})
            MNT_NAME="${HOME}/${MNT_NAME/enc_/}"
            # check to see if it has already been mounted
            MNTED=$(mount | grep "${MNT_NAME}")
            # check to see if dropbox has created any 'conflicted
            # copy' files in the encfs filesystem
            FOUND_CONFLICTED="$(find ${ENCFS} -name "*conflicted*" -exec sh -c 'if true; then ls -l "$1"; fi' -- {} \;)"

            # perform command
            case "${_CMD}" in
                # mount the filesystem
                mount)
                    # announce filesystem has conflicted files
                    if [[ ! -z "${FOUND_CONFLICTED}" ]] ; then
                        echo "!! Conflicted Files found in ${ENCFS} !!"
                    fi
                    # if not mounted
                    if [[ "${MNTED}" == "" ]] ; then
                        # if directory has no encfs filesystem, encfs
                        # assumes you want to create it, so give 'best'
                        # dropbox encfs settings hint
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
                # unmount fileystsem
                umount)
                    if [[ "${MNTED}" != "" ]] ; then 
                        fusermount -u ${MNT_NAME}
                        MNTED=$(mount | grep "${MNT_NAME}")
                        echo "-- unmounted"
                    fi
                    ;;
                # resolve conflicts
                conflicts)
                    # if conflicts found
                    if [[ ! -z "${FOUND_CONFLICTED}" ]] ; then
                        echo "!!!!!!!!!!!!! Resolving Conflicts !!!!!!!!!!!!"
                        echo "== Resolving for ${MNT_NAME} (${ENCFS}) "
                        echo "++ Enter Password:"
                        # read password for encfs filesystem and reset terminal back to sane
                        read -s MNT_PASSWD
                        stty sane

                        # iterate through every conflict
                        find ${ENCFS} -name "*conflicted*" -print0 | while read -d $'\0' CONFLICTED
                        do
                            # get original encfs filename
                            ORIGINAL=$(expr match "${CONFLICTED}" '\([^\(]*\) (.*conflicted copy.*)[^\)]*')
                            # get dropbox conflicted notification
                            CONFLICT=$(expr match "${CONFLICTED}" '[^\(]* (\(.*conflicted copy.*\))[^\)]*')
                            # get decoded encfs filensme
                            DECODED=$(encfsctl decode --extpass="echo ${MNT_PASSWD}" ${ENCFS} "${ORIGINAL}")
                            # create new encoded filename and encode it.
                            NEWNAME="${DECODED} (${CONFLICT})"
                            ENCODED=$(encfsctl encode --extpass="echo ${MNT_PASSWD}" ${ENCFS} "${NEWNAME}")

                            echo "+++++++++"
                            echo "--:${DECODED}"
                            echo "->:${NEWNAME}"
#                            echo "--:${CONFLICTED}"
#                            echo "->:${ENCODED}"
                            # move to new encfs filename with noclobber
                            mv -iv "${CONFLICTED}" "${ENCFS}/${ENCODED}"
                        done
                        echo "================================"
                    fi
                    ;;

                # dropbox/encfs status
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
usage: $0 <status|m or mount|u or umount|r or refresh|conflicts>

Commands:
status - display status of encfs mounts (default command)
mount - mount/create encfs filesystems in ${MNT_SEARCH}
umount - unmount encfs filesystems
refresh - silently check status and mount/create encfs filesystems if unmounted.
conflicts - perform conflicted copy file resolution.

See README for more details.

EOF
fi
