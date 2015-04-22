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

if [ -x /bin/echo ]; then
    ECHO='/bin/echo'
else
    ECHO='echo'
fi

msg() {
    echo "gen-install-script: ${1-}"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "gen-install-script: WARNING: $1" >&2
}

err() {
    echo "gen-install-script: error: $1" >&2
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
        printf "gen-install-script: %-20s := %.35s ...\n" $1 "$t"
    else
        printf "gen-install-script: %-20s := %s %s\n" $1 "$t"
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

# Prints the absolute path of a directory to stdout
abs_path() {
    local path="$1"
    # Unset CDPATH because it causes havok: it makes the destination unpredictable
    # and triggers 'cd' to print the path to stdout. Route `cd`'s output to /dev/null
    # for good measure.
    (unset CDPATH && cd "$path" > /dev/null && pwd)
}

msg "looking for install programs"
msg

need_cmd sed
need_cmd chmod
need_cmd cat

CFG_ARGS="$@"

HELP=0
if [ "$1" = "--help" ]
then
    HELP=1
    shift
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo
else
    step_msg "processing arguments"
fi

OPTIONS=""
BOOL_OPTIONS=""
VAL_OPTIONS=""

valopt product-name "Product" "The name of the product, for display"
valopt rel-manifest-dir "manifestlib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt output-script "install.sh" "The name of the output script"
valopt legacy-manifest-dirs "" "Places to look for legacy manifests to uninstall"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating arguments"
validate_opt

src_dir="$(abs_path $(dirname "$0"))"

rust_installer_version=`cat "$src_dir/rust-installer-version"`

# Replace dashes in the success message with spaces (our arg handling botches spaces)
product_name=`echo "$CFG_PRODUCT_NAME" | sed "s/-/ /g"`

# Replace dashes in the success message with spaces (our arg handling botches spaces)
success_message=`echo "$CFG_SUCCESS_MESSAGE" | sed "s/-/ /g"`

script_template=`cat "$src_dir/install-template.sh"`

# Using /bin/echo because under sh emulation dash *seems* to escape \n, which screws up the template
script=`$ECHO "$script_template"`
script=`$ECHO "$script" | sed "s/%%TEMPLATE_PRODUCT_NAME%%/\"$product_name\"/"`
script=`$ECHO "$script" | sed "s/%%TEMPLATE_REL_MANIFEST_DIR%%/$CFG_REL_MANIFEST_DIR/"`
script=`$ECHO "$script" | sed "s/%%TEMPLATE_SUCCESS_MESSAGE%%/\"$success_message\"/"`
script=`$ECHO "$script" | sed "s/%%TEMPLATE_LEGACY_MANIFEST_DIRS%%/\"$CFG_LEGACY_MANIFEST_DIRS\"/"`
script=`$ECHO "$script" | sed "s/%%TEMPLATE_RUST_INSTALLER_VERSION%%/\"$rust_installer_version\"/"`

$ECHO "$script" > "$CFG_OUTPUT_SCRIPT"
need_ok "couldn't write script"
chmod u+x "$CFG_OUTPUT_SCRIPT"
need_ok "couldn't chmod script"
