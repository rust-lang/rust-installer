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
    echo "combine-installers: ${1-}"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "combine-installers: WARNING: $1" >&2
}

err() {
    echo "combine-installers: error: $1" >&2
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
        printf "combine-installers: %-20s := %.35s ...\n" $1 "$t"
    else
        printf "combine-installers: %-20s := %s %s\n" $1 "$t"
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

msg "looking for programs"
msg

need_cmd tar
need_cmd cp
need_cmd rm
need_cmd mkdir
need_cmd echo
need_cmd tr

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
valopt package-name "package" "The name of the package, tarball"
valopt rel-manifest-dir "${CFG_PACKAGE_NAME}lib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt legacy-manifest-dirs "" "Places to look for legacy manifests to uninstall"
valopt input-tarballs "" "Installers to combine"
valopt non-installed-overlay "" "Directory containing files that should not be installed"
valopt work-dir "./workdir" "The directory to do temporary work and put the final image"
valopt output-dir "./dist" "The location to put the final tarball"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating arguments"
validate_opt

src_dir="$(abs_path $(dirname "$0"))"

rust_installer_version=`cat "$src_dir/rust-installer-version"`

# Create the work directory for the new installer
mkdir -p "$CFG_WORK_DIR"
need_ok "couldn't create work dir"

rm -Rf "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't delete work package dir"

mkdir -p "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't create work package dir"

input_tarballs=`echo "$CFG_INPUT_TARBALLS" | sed 's/,/ /g'`

# Merge each installer into the work directory of the new installer
for input_tarball in $input_tarballs; do

    # Extract the input tarballs
    tar xzf $input_tarball -C "$CFG_WORK_DIR"
    need_ok "failed to extract tarball"

    # Verify the version number
    pkg_name=`echo "$input_tarball" | sed s/\.tar\.gz//g`
    pkg_name=`basename $pkg_name`
    version=`cat "$CFG_WORK_DIR/$pkg_name/rust-installer-version"`
    if [ "$rust_installer_version" != "$version" ]; then
	err "incorrect installer version in $input_tarball"
    fi

    # Copy components to new combined installer
    components=`cat "$CFG_WORK_DIR/$pkg_name/components"`
    for component in $components; do

	# All we need to do is copy the component directory
	cp -R "$CFG_WORK_DIR/$pkg_name/$component" "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$component"
	need_ok "failed to copy component $component"

	# Merge the component name
	echo "$component" >> "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/components"
	need_ok "failed to merge component $component"
    done
done

# Write the version number
echo "$rust_installer_version" > "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/rust-installer-version"

# Copy the overlay
if [ -n "$CFG_NON_INSTALLED_OVERLAY" ]; then
    overlay_files=`(cd "$CFG_NON_INSTALLED_OVERLAY" && find . -type f)`
    for f in $overlay_files; do
	if [ -e "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$f" ]; then err "overlay $f exists"; fi

	cp "$CFG_NON_INSTALLED_OVERLAY/$f" "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$f"
	need_ok "failed to copy overlay $f"
    done
fi

# Generate the install script
"$src_dir/gen-install-script.sh" \
    --product-name="$CFG_PRODUCT_NAME" \
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
