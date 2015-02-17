#!/bin/sh
# Copyright 2014 The Rust Project Developers. See the COPYRIGHT
# file at the top-level directory of this distribution and at
# http://rust-lang.org/COPYRIGHT.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
# option. This file may not be copied, modified, or distributed
# except according to those terms.

msg() {
    echo "gen-install-script: $1"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "gen-install-script: WARNING: $1"
}

err() {
    echo "gen-install-script: error: $1"
    exit 1
}

need_ok() {
    if [ $? -ne 0 ]
    then
        err "$1"
    fi
}

need_cmd() {
    if command -v $1 >/dev/null 2>&1
    then msg "found $1"
    else err "need $1"
    fi
}

putvar() {
    local T
    eval T=\$$1
    eval TLEN=\${#$1}
    if [ $TLEN -gt 35 ]
    then
        printf "gen-install-script: %-20s := %.35s ...\n" $1 "$T"
    else
        printf "gen-install-script: %-20s := %s %s\n" $1 "$T" "$2"
    fi
}

valopt() {
    VAL_OPTIONS="$VAL_OPTIONS $1"

    local OP=$1
    local DEFAULT=$2
    shift
    shift
    local DOC="$*"
    if [ $HELP -eq 0 ]
    then
        local UOP=$(echo $OP | tr '[:lower:]' '[:upper:]' | tr '\-' '\_')
        local V="CFG_${UOP}"
        eval $V="$DEFAULT"
        for arg in $CFG_ARGS
        do
            if echo "$arg" | grep -q -- "--$OP="
            then
                val=$(echo "$arg" | cut -f2 -d=)
                eval $V=$val
            fi
        done
        putvar $V
    else
        if [ -z "$DEFAULT" ]
        then
            DEFAULT="<none>"
        fi
        OP="${OP}=[${DEFAULT}]"
        printf "    --%-30s %s\n" "$OP" "$DOC"
    fi
}

opt() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local OP=$1
    local DEFAULT=$2
    shift
    shift
    local DOC="$*"
    local FLAG=""

    if [ $DEFAULT -eq 0 ]
    then
        FLAG="enable"
    else
        FLAG="disable"
        DOC="don't $DOC"
    fi

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${FLAG}-${OP}" ]
            then
                OP=$(echo $OP | tr 'a-z-' 'A-Z_')
                FLAG=$(echo $FLAG | tr 'a-z' 'A-Z')
                local V="CFG_${FLAG}_${OP}"
                eval $V=1
                putvar $V
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            OP="$OP=<$META>"
        fi
        printf "    --%-30s %s\n" "$FLAG-$OP" "$DOC"
     fi
}

flag() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local OP=$1
    shift
    local DOC="$*"

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${OP}" ]
            then
                OP=$(echo $OP | tr 'a-z-' 'A-Z_')
                local V="CFG_${OP}"
                eval $V=1
                putvar $V
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            OP="$OP=<$META>"
        fi
        printf "    --%-30s %s\n" "$OP" "$DOC"
     fi
}

validate_opt () {
    for arg in $CFG_ARGS
    do
        isArgValid=0
        for option in $BOOL_OPTIONS
        do
            if test --disable-$option = $arg
            then
                isArgValid=1
            fi
            if test --enable-$option = $arg
            then
                isArgValid=1
            fi
            if test --$option = $arg
            then
                isArgValid=1
            fi
        done
        for option in $VAL_OPTIONS
        do
            if echo "$arg" | grep -q -- "--$option="
            then
                isArgValid=1
            fi
        done
        if [ "$arg" = "--help" ]
        then
            echo
            echo "No more help available for Configure options,"
            echo "check the Wiki or join our IRC channel"
            break
        else
            if test $isArgValid -eq 0
            then
                err "Option '$arg' is not recognized"
            fi
        fi
    done
}

msg "looking for install programs"
msg

need_cmd sed
need_cmd chmod
need_cmd cat

CFG_SRC_DIR="$(cd $(dirname $0) && pwd)"
CFG_SELF="$0"
CFG_ARGS="$@"

HELP=0
if [ "$1" = "--help" ]
then
    HELP=1
    shift
    echo
    echo "Usage: $CFG_SELF [options]"
    echo
    echo "Options:"
    echo
else
    step_msg "processing $CFG_SELF args"
fi

valopt product-name "Product" "The name of the product, for display"
valopt verify-bin "program" "The command to run with --version to verify the install works"
valopt rel-manifest-dir "${CFG_VERIFY_BIN}lib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt output-script "${CFG_SRC_DIR}/install.sh" "The name of the output script"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating $CFG_SELF args"
validate_opt

# Replace dashes in the success message with spaces (our arg handling botches spaces)
CFG_SUCCESS_MESSAGE=`echo "$CFG_SUCCESS_MESSAGE" | sed "s/-/ /g"`

SCRIPT_TEMPLATE=`cat "${CFG_SRC_DIR}/install-template.sh"`

# Using /bin/echo because under sh emulation dash *seems* to escape \n, which screws up the template
SCRIPT=`/bin/echo "${SCRIPT_TEMPLATE}"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_PRODUCT_NAME%%/${CFG_PRODUCT_NAME}/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_VERIFY_BIN%%/${CFG_VERIFY_BIN}/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_REL_MANIFEST_DIR%%/${CFG_REL_MANIFEST_DIR}/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_SUCCESS_MESSAGE%%/\"${CFG_SUCCESS_MESSAGE}\"/"`

/bin/echo "${SCRIPT}" > "${CFG_OUTPUT_SCRIPT}"
need_ok "couldn't write script"
chmod u+x "${CFG_OUTPUT_SCRIPT}"
need_ok "couldn't chmod script"
