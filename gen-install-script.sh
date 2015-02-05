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

set -u

msg() {
    echo "install: ${1-}"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "install: WARNING: $1" >&2
}

err() {
    echo "install: error: $1" >&2
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
    local t
    local tlen
    eval t=\$$1
    eval tlen=\${#$1}
    if [ $tlen -gt 35 ]
    then
        printf "install: %-20s := %.35s ...\n" $1 "$t"
    else
        printf "install: %-20s := %s %s\n" $1 "$t"
    fi
}

valopt() {
    VAL_OPTIONS="$VAL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    if [ $HELP -eq 0 ]
    then
        local uop=$(echo $op | tr '[:lower:]' '[:upper:]' | tr '\-' '\_')
        local v="CFG_${uop}"
        eval $v="$default"
        for arg in $CFG_ARGS
        do
            if echo "$arg" | grep -q -- "--$op="
            then
                local val=$(echo "$arg" | cut -f2 -d=)
                eval $v=$val
            fi
        done
        putvar $v
    else
        if [ -z "$default" ]
        then
            default="<none>"
        fi
        op="${default}=[${default}]"
        printf "    --%-30s %s\n" "$op" "$doc"
    fi
}

opt() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    local flag=""

    if [ $default -eq 0 ]
    then
        flag="enable"
    else
        flag="disable"
        doc="don't $doc"
    fi

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${flag}-${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                flag=$(echo $flag | tr 'a-z' 'A-Z')
                local v="CFG_${flag}_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$flag-$op" "$doc"
     fi
}

flag() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    shift
    local doc="$*"

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                local v="CFG_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$op" "$doc"
     fi
}

validate_opt () {
    for arg in $CFG_ARGS
    do
        local is_arg_valid=0
        for option in $BOOL_OPTIONS
        do
            if test --disable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --enable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --$option = $arg
            then
                is_arg_valid=1
            fi
        done
        for option in $VAL_OPTIONS
        do
            if echo "$arg" | grep -q -- "--$option="
            then
                is_arg_valid=1
            fi
        done
        if [ "$arg" = "--help" ]
        then
            echo
            echo "No more help available for Configure options,"
            echo "check the Wiki or join our IRC channel"
            break
        else
            if test $is_arg_valid -eq 0
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

OPTIONS=""
BOOL_OPTIONS=""
VAL_OPTIONS=""

valopt product-name "Product" "The name of the product, for display"
valopt verify-bin "" "The command to run with --version to verify the install works"
valopt rel-manifest-dir "${CFG_VERIFY_BIN}lib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt output-script "${CFG_SRC_DIR}/install.sh" "The name of the output script"
valopt legacy-manifest-dirs "" "Places to look for legacy manifests to uninstall"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating $CFG_SELF args"
validate_opt

RUST_INSTALLER_VERSION=`cat "$CFG_SRC_DIR/rust-installer-version"`

# Replace dashes in the success message with spaces (our arg handling botches spaces)
CFG_PRODUCT_NAME=`echo "$CFG_PRODUCT_NAME" | sed "s/-/ /g"`

# Replace dashes in the success message with spaces (our arg handling botches spaces)
CFG_SUCCESS_MESSAGE=`echo "$CFG_SUCCESS_MESSAGE" | sed "s/-/ /g"`

SCRIPT_TEMPLATE=`cat "${CFG_SRC_DIR}/install-template.sh"`

# Using /bin/echo because under sh emulation dash *seems* to escape \n, which screws up the template
SCRIPT=`/bin/echo "${SCRIPT_TEMPLATE}"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_PRODUCT_NAME%%/\"${CFG_PRODUCT_NAME}\"/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_VERIFY_BIN%%/${CFG_VERIFY_BIN}/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_REL_MANIFEST_DIR%%/${CFG_REL_MANIFEST_DIR}/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_SUCCESS_MESSAGE%%/\"${CFG_SUCCESS_MESSAGE}\"/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_LEGACY_MANIFEST_DIRS%%/\"${CFG_LEGACY_MANIFEST_DIRS}\"/"`
SCRIPT=`/bin/echo "${SCRIPT}" | sed "s/%%TEMPLATE_RUST_INSTALLER_VERSION%%/\"$RUST_INSTALLER_VERSION\"/"`

/bin/echo "${SCRIPT}" > "${CFG_OUTPUT_SCRIPT}"
need_ok "couldn't write script"
chmod u+x "${CFG_OUTPUT_SCRIPT}"
need_ok "couldn't chmod script"
