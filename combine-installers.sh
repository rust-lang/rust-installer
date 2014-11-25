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
    echo "combine-installers: $1"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "combine-installers: WARNING: $1"
}

err() {
    echo "combine-installers: error: $1"
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
        printf "combine-installers: %-20s := %.35s ...\n" $1 "$T"
    else
        printf "combine-installers: %-20s := %s %s\n" $1 "$T" "$2"
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
valopt package-name "package" "The name of the package, tarball"
valopt verify-bin "program" "The command to run with --version to verify the install works"
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

step_msg "validating $CFG_SELF args"
validate_opt

RUST_INSTALLER_VERSION=`cat "$CFG_SRC_DIR/rust-installer-version"`

# Create the work directory for the new installer
mkdir -p "$CFG_WORK_DIR"
need_ok "couldn't create work dir"

rm -Rf "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't delete work package dir"

mkdir -p "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't create work package dir"

INPUT_TARBALLS=`echo "$CFG_INPUT_TARBALLS" | sed 's/,/ /g'`

# Merge each installer into the work directory of the new installer
for input_tarball in $INPUT_TARBALLS; do

    # Extract the input tarballs
    tar xzf $input_tarball -C "$CFG_WORK_DIR"
    need_ok "failed to extract tarball"

    # Verify the version number
    PKG_NAME=`echo "$input_tarball" | sed s/\.tar\.gz//g`
    PKG_NAME=`basename $PKG_NAME`
    VERSION=`cat "$CFG_WORK_DIR/$PKG_NAME/rust-installer-version"`
    if [ "$RUST_INSTALLER_VERSION" != "$VERSION" ]; then
	err "incorrect installer version in $input_tarball"
    fi

    # Interpret the manifest to copy the contents to the new installer
    COMPONENTS=`cat "$CFG_WORK_DIR/$PKG_NAME/components"`
    for component in $COMPONENTS; do
	while read directive; do
	    COMMAND=`echo $directive | cut -f1 -d:`
	    FILE=`echo $directive | cut -f2 -d:`

	    NEW_FILE_PATH="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$FILE"
	    mkdir -p "$(dirname $NEW_FILE_PATH)"

	    case "$COMMAND" in
		file | dir)
		    if [ -e "$NEW_FILE_PATH" ]; then
			err "file $NEW_FILE_PATH already exists"
		    fi
		    cp -R "$CFG_WORK_DIR/$PKG_NAME/$FILE" "$NEW_FILE_PATH"
		    need_ok "failed to copy file $FILE"
		    ;;

		* )
		    err "unknown command"
		    ;;

	    esac
	done < "$CFG_WORK_DIR/$PKG_NAME/manifest-$component.in"

	# Copy the manifest
	if [ -e "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/manifest-$component.in" ]; then
	    err "manifest for $component already exists"
	fi
	cp "$CFG_WORK_DIR/$PKG_NAME/manifest-$component.in" "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/manifest-$component.in"
	need_ok "failed to copy manifest for $component"

	# Merge the component name
	echo "$component" >> "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/components"
	need_ok "failed to merge component $component"
    done
done

# Write the version number
echo "$RUST_INSTALLER_VERSION" > "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/rust-installer-version"

# Copy the overlay
if [ -n "$CFG_NON_INSTALLED_OVERLAY" ]; then
    OVERLAY_FILES=`(cd "$CFG_NON_INSTALLED_OVERLAY" && find . -type f)`
    for f in $OVERLAY_FILES; do
	if [ -e "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$f" ]; then err "overlay $f exists"; fi

	cp "$CFG_NON_INSTALLED_OVERLAY/$f" "$CFG_WORK_DIR/$CFG_PACKAGE_NAME/$f"
	need_ok "failed to copy overlay $f"
    done
fi

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
