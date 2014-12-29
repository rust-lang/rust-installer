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
    echo "gen-installer: $1"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "gen-installer: WARNING: $1"
}

err() {
    echo "gen-installer: error: $1"
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
        printf "gen-installer: %-20s := %.35s ...\n" $1 "$T"
    else
        printf "gen-installer: %-20s := %s %s\n" $1 "$T" "$2"
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

msg "looking for programs"
msg

need_cmd tar
need_cmd cp
need_cmd rm
need_cmd mkdir
need_cmd echo
need_cmd tr
need_cmd awk

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
valopt component-name "component" "The name of the component, distinct from other installed components"
valopt package-name "package" "The name of the package, tarball"
valopt verify-bin "" "The command to run with --version to verify the install works"
valopt rel-manifest-dir "${CFG_PACKAGE_NAME}lib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt legacy-manifest-dirs "" "Places to look for legacy manifests to uninstall"
valopt non-installed-prefixes "" "Path prefixes that should be included but not installed"
valopt bulk-dirs "" "Path prefixes of directories that should be installed/uninstalled in bulk"
valopt image-dir "./install-image" "The directory containing the installation medium"
valopt work-dir "./workdir" "The directory to do temporary work"
valopt output-dir "./dist" "The location to put the final image and tarball"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating $CFG_SELF args"
validate_opt

RUST_INSTALLER_VERSION=`cat "$CFG_SRC_DIR/rust-installer-version"`

if [ ! -d "$CFG_IMAGE_DIR" ]
then
    err "image dir $CFG_IMAGE_DIR does not exist"
fi

mkdir -p "$CFG_WORK_DIR"
need_ok "couldn't create work dir"

rm -Rf "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't delete work package dir"

mkdir -p "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't create work package dir"

cp -r "$CFG_IMAGE_DIR/"* "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't copy source image"

# Create the manifest
MANIFEST=`(cd "$CFG_WORK_DIR/$CFG_PACKAGE_NAME" && find . -type f | sed 's/^\.\///') | sort`

# Remove non-installed files from manifest
NON_INSTALLED_PREFIXES=`echo "$CFG_NON_INSTALLED_PREFIXES" | tr "," " "`
for prefix in $NON_INSTALLED_PREFIXES; do
    # This adds the escapes to '/' in paths to make them '\/' so sed doesn't puke.
    # I figured this out by adding backslashes until it worked. Holy shit.
    prefix=`echo "$prefix" | sed s/\\\//\\\\\\\\\\\//g`
    MANIFEST=`echo "$MANIFEST" | sed /^$prefix/d`
done

# Remove files in bulk dirs
BULK_DIRS=`echo "$CFG_BULK_DIRS" | tr "," " "`
for bulk_dir in $BULK_DIRS; do
    bulk_dir=`echo "$bulk_dir" | sed s/\\\//\\\\\\\\\\\//g`
    MANIFEST=`echo "$MANIFEST" | sed /^$bulk_dir/d`
done

# Add 'file:' installation directives.
# The -n prevents adding a blank file: if the manifest is empty
MANIFEST=`/bin/echo -n "$MANIFEST" | sed s/^/file:/`

# Add 'dir:' directives
for bulk_dir in $BULK_DIRS; do
    MANIFEST=`echo "$MANIFEST" && echo "dir:$bulk_dir"`
done

# The above step may have left a leading empty line if there were only
# bulk dirs. Remove it.
MANIFEST=`echo "$MANIFEST" | sed /^$/d`

MANIFEST_FILE="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/manifest-$CFG_COMPONENT_NAME.in"
COMPONENT_FILE="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/components"
VERSION_FILE="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/rust-installer-version"

# Write the manifest
echo "$MANIFEST" > "$MANIFEST_FILE"

# Write the component name
echo "$CFG_COMPONENT_NAME" > "$COMPONENT_FILE"

# Write the installer version (only used by combine-installers.sh)
echo "$RUST_INSTALLER_VERSION" > "$VERSION_FILE"

# Generate the install script
"$CFG_SRC_DIR/gen-install-script.sh" \
    --product-name="$CFG_PRODUCT_NAME" \
    --verify-bin="$CFG_VERIFY_BIN" \
    --rel-manifest-dir="$CFG_REL_MANIFEST_DIR" \
    --success-message="$CFG_SUCCESS_MESSAGE" \
    --legacy-manifest-dirs="$CFG_LEGACY_MANIFEST_DIRS" \
    --output-script="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/install.sh"

need_ok "failed to generate install script"    

mkdir -p "$CFG_OUTPUT_DIR"
need_ok "couldn't create output dir"

rm -Rf "$CFG_OUTPUT_DIR/$CFG_PACKAGE_NAME.tar.gz"
need_ok "couldn't delete old tarball"

# Make a tarball
tar -czf "$CFG_OUTPUT_DIR/$CFG_PACKAGE_NAME.tar.gz" -C "$CFG_WORK_DIR" "$CFG_PACKAGE_NAME"
need_ok "failed to tar"
