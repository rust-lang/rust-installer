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
    echo "install: $1"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "install: WARNING: $1"
}

err() {
    echo "install: error: $1"
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
        printf "install: %-20s := %.35s ...\n" $1 "$T"
    else
        printf "install: %-20s := %s %s\n" $1 "$T" "$2"
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

absolutify() {
    FILE_PATH="${1}"
    FILE_PATH_DIRNAME="$(dirname ${FILE_PATH})"
    FILE_PATH_BASENAME="$(basename ${FILE_PATH})"
    FILE_ABS_PATH="$(cd ${FILE_PATH_DIRNAME} && pwd)"
    FILE_PATH="${FILE_ABS_PATH}/${FILE_PATH_BASENAME}"
    # This is the return value
    ABSOLUTIFIED="${FILE_PATH}"
}

msg "looking for install programs"
msg

need_cmd mkdir
need_cmd printf
need_cmd cut
need_cmd grep
need_cmd uname
need_cmd tr
need_cmd sed

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

# Check for mingw or cygwin in order to special case $CFG_LIBDIR_RELATIVE.
# This logic is duplicated from configure in order to get the correct libdir
# for Windows installs.
CFG_OSTYPE=$(uname -s)

case $CFG_OSTYPE in

    Linux)
        CFG_OSTYPE=unknown-linux-gnu
        ;;

    FreeBSD)
        CFG_OSTYPE=unknown-freebsd
        ;;

    DragonFly)
        CFG_OSTYPE=unknown-dragonfly
        ;;

    Darwin)
        CFG_OSTYPE=apple-darwin
        ;;

    MINGW*)
        # msys' `uname` does not print gcc configuration, but prints msys
        # configuration. so we cannot believe `uname -m`:
        # msys1 is always i686 and msys2 is always x86_64.
        # instead, msys defines $MSYSTEM which is MINGW32 on i686 and
        # MINGW64 on x86_64.
        CFG_CPUTYPE=i686
        CFG_OSTYPE=pc-windows-gnu
        if [ "$MSYSTEM" = MINGW64 ]
        then
            CFG_CPUTYPE=x86_64
        fi
        ;;

    MSYS*)
        CFG_OSTYPE=pc-windows-gnu
        ;;

# Thad's Cygwin identifers below

#   Vista 32 bit
    CYGWIN_NT-6.0)
        CFG_OSTYPE=pc-windows-gnu
        CFG_CPUTYPE=i686
        ;;

#   Vista 64 bit
    CYGWIN_NT-6.0-WOW64)
        CFG_OSTYPE=pc-windows-gnu
        CFG_CPUTYPE=x86_64
        ;;

#   Win 7 32 bit
    CYGWIN_NT-6.1)
        CFG_OSTYPE=pc-windows-gnu
        CFG_CPUTYPE=i686
        ;;

#   Win 7 64 bit
    CYGWIN_NT-6.1-WOW64)
        CFG_OSTYPE=pc-windows-gnu
        CFG_CPUTYPE=x86_64
        ;;
esac

OPTIONS=""
BOOL_OPTIONS=""
VAL_OPTIONS=""

if [ "$CFG_OSTYPE" = "pc-windows-gnu" ]
then
    CFG_LD_PATH_VAR=PATH
    CFG_OLD_LD_PATH_VAR=$PATH
elif [ "$CFG_OSTYPE" = "apple-darwin" ]
then
    CFG_LD_PATH_VAR=DYLD_LIBRARY_PATH
    CFG_OLD_LD_PATH_VAR=$DYLD_LIBRARY_PATH
else
    CFG_LD_PATH_VAR=LD_LIBRARY_PATH
    CFG_OLD_LD_PATH_VAR=$LD_LIBRARY_PATH
fi

flag uninstall "only uninstall from the installation prefix"
valopt destdir "" "set installation root"
opt verify 1 "verify that the installed binaries run correctly"
valopt prefix "/usr/local" "set installation prefix"
# NB This isn't quite the same definition as in `configure`.
# just using 'lib' instead of configure's CFG_LIBDIR_RELATIVE
valopt libdir "${CFG_DESTDIR}${CFG_PREFIX}/lib" "install libraries"
valopt mandir "${CFG_DESTDIR}${CFG_PREFIX}/share/man" "install man pages in PATH"
opt ldconfig 1 "run ldconfig after installation (Linux only)"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating $CFG_SELF args"
validate_opt

# Template configuration.
# These names surrounded by '%%` are replaced by sed when generating install.sh
# FIXME: Might want to consider loading this from a file and not generating install.sh

# Rust or Cargo
TEMPLATE_PRODUCT_NAME=%%TEMPLATE_PRODUCT_NAME%%
# rustc or cargo
TEMPLATE_VERIFY_BIN=%%TEMPLATE_VERIFY_BIN%%
# rustlib or cargo
TEMPLATE_REL_MANIFEST_DIR=%%TEMPLATE_REL_MANIFEST_DIR%%
# 'Rust is ready to roll.' or 'Cargo is cool to cruise.'
TEMPLATE_SUCCESS_MESSAGE=%%TEMPLATE_SUCCESS_MESSAGE%%
# Locations to look for directories containing legacy, pre-versioned manifests
TEMPLATE_LEGACY_MANIFEST_DIRS=%%TEMPLATE_LEGACY_MANIFEST_DIRS%%
# The installer version
TEMPLATE_RUST_INSTALLER_VERSION=%%TEMPLATE_RUST_INSTALLER_VERSION%%

# OK, let's get installing ...

# If we don't have a verify bin then disable verify
if [ -z "$TEMPLATE_VERIFY_BIN" ]; then
    CFG_DISABLE_VERIFY=1
fi

# Sanity check: can we run the binaries?
if [ -z "${CFG_DISABLE_VERIFY}" ]
then
    # Don't do this if uninstalling. Failure here won't help in any way.
    if [ -z "${CFG_UNINSTALL}" ]
    then
        msg "verifying platform can run binaries"
        export $CFG_LD_PATH_VAR="${CFG_SRC_DIR}/lib:$CFG_OLD_LD_PATH_VAR"
        "${CFG_SRC_DIR}/bin/${TEMPLATE_VERIFY_BIN}" --version 2> /dev/null 1> /dev/null
        if [ $? -ne 0 ]
        then
            err "can't execute binaries on this platform"
        fi
        export $CFG_LD_PATH_VAR="$CFG_OLD_LD_PATH_VAR"
    fi
fi

# Sanity check: can we can write to the destination?
msg "verifying destination is writable"
umask 022 && mkdir -p "${CFG_LIBDIR}"
need_ok "can't write to destination. consider \`sudo\`."
touch "${CFG_LIBDIR}/rust-install-probe" > /dev/null
if [ $? -ne 0 ]
then
    err "can't write to destination. consider \`sudo\`."
fi
rm -f "${CFG_LIBDIR}/rust-install-probe"
need_ok "failed to remove install probe"

# Sanity check: don't install to the directory containing the installer.
# That would surely cause chaos.
msg "verifying destination is not the same as source"
INSTALLER_DIR="$(cd $(dirname $0) && pwd)"
PREFIX_DIR="$(cd ${CFG_PREFIX} && pwd)"
if [ "${INSTALLER_DIR}" = "${PREFIX_DIR}" ]
then
    err "can't install to same directory as installer"
fi

# Open the components file to get the list of components to install
COMPONENTS=`cat "$CFG_SRC_DIR/components"`

# Sanity check: do we have components?
if [ ! -n "$COMPONENTS" ]; then
    err "unable to find installation components"
fi

# Using an absolute path to libdir in a few places so that the status
# messages are consistently using absolute paths.
absolutify "${CFG_LIBDIR}"
ABS_LIBDIR="${ABSOLUTIFIED}"

# Replace commas in legacy manifest list with spaces
LEGACY_MANIFEST_DIRS=`echo "$TEMPLATE_LEGACY_MANIFEST_DIRS" | sed "s/,/ /g"`

# Uninstall from legacy manifests
for md in $LEGACY_MANIFEST_DIRS; do
    # First, uninstall from the installation prefix.
    # Errors are warnings - try to rm everything in the manifest even if some fail.
    if [ -f "$ABS_LIBDIR/$md/manifest" ]
    then

	# Iterate through installed manifest and remove files
	while read p; do
            # The installed manifest contains absolute paths
            msg "removing legacy file $p"
            if [ -f "$p" ]
            then
		rm -f "$p"
		if [ $? -ne 0 ]
		then
                    warn "failed to remove $p"
		fi
            else
		warn "supposedly installed file $p does not exist!"
            fi
	done < "$ABS_LIBDIR/$md/manifest"

	# If we fail to remove $md below, then the
	# installed manifest will still be full; the installed manifest
	# needs to be empty before install.
	msg "removing legacy manifest $ABS_LIBDIR/$md/manifest"
	rm -f "$ABS_LIBDIR/$md/manifest"
	# For the above reason, this is a hard error
	need_ok "failed to remove installed manifest"

	# Remove $TEMPLATE_REL_MANIFEST_DIR directory
	msg "removing legacy manifest dir ${ABS_LIBDIR}/$md"
	rm -Rf "${ABS_LIBDIR}/$md"
	if [ $? -ne 0 ]
	then
            warn "failed to remove $md"
	fi

	UNINSTALLED_SOMETHING=1
    fi
done

# Load the version of the installed installer
if [ -f "$ABS_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version" ]; then
    INSTALLED_VERSION=`cat "$ABS_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version"`

    # Sanity check
    if [ ! -n "$INSTALLED_VERSION" ]; then err "rust installer version is empty"; fi
fi

# If there's something installed, then uninstall
if [ -n "$INSTALLED_VERSION" ]; then
    # Check the version of the installed installer
    case "$INSTALLED_VERSION" in

	# TODO: If this is a previous version, then upgrade in place to the
	# current version before uninstalling. No need to do this yet because
	# there is no prior version (only the legacy 'unversioned' installer
	# which we've already dealt with).

	# This is the current version. Nothing need to be done except uninstall.
	"$TEMPLATE_RUST_INSTALLER_VERSION")
	    ;;

	# TODO: If this is an unknown (future) version then bail.
	*)
	    echo "The copy of $TEMPLATE_PRODUCT_NAME at $CFG_PREFIX was installed using an"
	    echo "unknown version ($INSTALLED_VERSION) of rust-installer."
	    echo "Uninstall it first with the installer used for the original installation"
	    echo "before continuing."
	    exit 1
	    ;;
    esac

    MD="$ABS_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"
    INSTALLED_COMPONENTS=`cat $MD/components`

    # Uninstall (our components only) before reinstalling
    for available_component in $COMPONENTS; do
	for installed_component in $INSTALLED_COMPONENTS; do
	    if [ "$available_component" = "$installed_component" ]; then
		COMPONENT_MANIFEST="$MD/manifest-$installed_component"

		# Sanity check: there should be a component manifest
		if [ ! -f "$COMPONENT_MANIFEST" ]; then
		    err "installed component '$installed_component' has no manifest"
		fi

		# Iterate through installed component manifest and remove files
		while read directive; do

		    COMMAND=`echo $directive | cut -f1 -d:`
		    FILE=`echo $directive | cut -f2 -d:`

		    # Sanity checks
		    if [ ! -n "$COMMAND" ]; then err "malformed installation directive"; fi
		    if [ ! -n "$FILE" ]; then err "malformed installation directive"; fi

		    case "$COMMAND" in
			file)
			    msg "removing file $FILE"
			    if [ -f "$FILE" ]; then
				rm -f "$FILE"
				if [ $? -ne 0 ]; then
				    warn "failed to remove $FILE"
				fi
			    else
				warn "supposedly installed file $FILE does not exist!"
			    fi
			    ;;

			dir)
			    msg "removing directory $FILE"
			    rm -Rf "$FILE"
			    if [ $? -ne 0]; then
				warn "unable to remove directory $FILE"
			    fi
			    ;;

			*)
			    err "unknown installation directive"
			    ;;
		    esac

		done < "$COMPONENT_MANIFEST"

		# Remove the installed component manifest
		msg "removing component manifest $COMPONENT_MANIFEST"
		rm -f "$COMPONENT_MANIFEST"
		# This is a hard error because the installation is unrecoverable
		need_ok "failed to remove installed manifest for component '$installed_component'"

		# Update the installed component list
		MODIFIED_COMPONENTS=`sed /^$installed_component\$/d $MD/components`
		echo "$MODIFIED_COMPONENTS" > "$MD/components"
		need_ok "failed to update installed component list"
	    fi
	done
    done

    # If there are no remaining components delete the manifest directory
    REMAINING_COMPONENTS=`cat $MD/components`
    if [ ! -n "$REMAINING_COMPONENTS" ]; then
	msg "removing manifest directory $MD"
	rm -Rf "$MD"
	if [ $? -ne 0 ]; then
	    warn "failed to remove $MD"
	fi
    fi

    UNINSTALLED_SOMETHING=1
fi

# There's no installed version. If we were asked to uninstall, then that's a problem.
if [ -n "${CFG_UNINSTALL}" -a ! -n "$UNINSTALLED_SOMETHING" ]
then
    err "unable to find installation manifest at ${CFG_LIBDIR}/${TEMPLATE_REL_MANIFEST_DIR}"
fi

# If we're only uninstalling then exit
if [ -n "${CFG_UNINSTALL}" ]
then
    echo
    echo "    ${TEMPLATE_PRODUCT_NAME} is uninstalled."
    echo
    exit 0
fi

# Create the directory to contain the manifests
mkdir -p "${CFG_LIBDIR}/${TEMPLATE_REL_MANIFEST_DIR}"
need_ok "failed to create ${TEMPLATE_REL_MANIFEST_DIR}"

# Install each component
for component in $COMPONENTS; do

    # The file name of the manifest we're installing from
    INPUT_MANIFEST="${CFG_SRC_DIR}/manifest-$component.in"

    # The installed manifest directory
    MD="$ABS_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"

    # The file name of the manifest we're going to create during install
    INSTALLED_MANIFEST="$MD/manifest-$component"

    # Create the installed manifest, which we will fill in with absolute file paths
    touch "${INSTALLED_MANIFEST}"
    need_ok "failed to create installed manifest"

    # Sanity check: do we have our input manifests?
    if [ ! -f "$INPUT_MANIFEST" ]; then
	err "manifest for $component does not exist at $INPUT_MANIFEST"
    fi

    # Now install, iterate through the new manifest and copy files
    while read directive; do

	COMMAND=`echo $directive | cut -f1 -d:`
	FILE=`echo $directive | cut -f2 -d:`

	# Sanity checks
	if [ ! -n "$COMMAND" ]; then err "malformed installation directive"; fi
	if [ ! -n "$FILE" ]; then err "malformed installation directive"; fi

	# Decide the destination of the file
	FILE_INSTALL_PATH="${CFG_DESTDIR}${CFG_PREFIX}/$FILE"

	if echo "$FILE" | grep "^lib/" > /dev/null
	then
            f=`echo $FILE | sed 's/^lib\///'`
            FILE_INSTALL_PATH="${CFG_LIBDIR}/$f"
	fi

	if echo "$FILE" | grep "^share/man/" > /dev/null
	then
            f=`echo $FILE | sed 's/^share\/man\///'`
            FILE_INSTALL_PATH="${CFG_MANDIR}/$f"
	fi

	# Make sure there's a directory for it
	umask 022 && mkdir -p "$(dirname ${FILE_INSTALL_PATH})"
	need_ok "directory creation failed"

	# Make the path absolute so we can uninstall it later without
	# starting from the installation cwd
	absolutify "${FILE_INSTALL_PATH}"
	FILE_INSTALL_PATH="${ABSOLUTIFIED}"

	case "$COMMAND" in
	    file)

		# Install the file
		msg "copying file $FILE_INSTALL_PATH"
		if echo "$FILE" | grep "^bin/" > /dev/null
		then
		    install -m755 "${CFG_SRC_DIR}/$FILE" "${FILE_INSTALL_PATH}"
		else
		    install -m644 "${CFG_SRC_DIR}/$FILE" "${FILE_INSTALL_PATH}"
		fi
		need_ok "file creation failed"

		# Update the manifest
		echo "file:${FILE_INSTALL_PATH}" >> "${INSTALLED_MANIFEST}"
		need_ok "failed to update manifest"

		;;

	    dir)

		# Copy the dir
		msg "copying directory $FILE_INSTALL_PATH"

		# Sanity check: bulk dirs are supposed to be uniquely ours and should not exist
		if [ -e "$FILE_INSTALL_PATH" ]; then
		    err "$FILE_INSTALL_PATH already exists"
		fi

		cp -R "$CFG_SRC_DIR/$FILE" "$FILE_INSTALL_PATH"
		need_ok "failed to copy directory"

		# Update the manifest
		echo "dir:$FILE_INSTALL_PATH" >> "$INSTALLED_MANIFEST"
		need_ok "failed to update manifest"
		;;

	    *)
		err "unknown installation directive"
		;;
	esac
    done < "$INPUT_MANIFEST"

    # Update the components
    echo "$component" >> "$MD/components"
    need_ok "failed to update components list for $component"

done

# Drop the version number into the manifest dir
echo "$TEMPLATE_RUST_INSTALLER_VERSION" > "${ABS_LIBDIR}/${TEMPLATE_REL_MANIFEST_DIR}/rust-installer-version"

# Run ldconfig to make dynamic libraries available to the linker
if [ "$CFG_OSTYPE" = "unknown-linux-gnu" -a ! -n "$CFG_DISABLE_LDCONFIG" ]; then
    msg "running ldconfig"
    ldconfig
    if [ $? -ne 0 ]
    then
        warn "failed to run ldconfig."
        warn "this may happen when not installing as root and may be fine"
    fi
fi

# Sanity check: can we run the installed binaries?
#
# As with the verification above, make sure the right LD_LIBRARY_PATH-equivalent
# is in place. Try first without this variable, and if that fails try again with
# the variable. If the second time tries, print a hopefully helpful message to
# add something to the appropriate environment variable.
if [ -z "${CFG_DISABLE_VERIFY}" ]
then
    export $CFG_LD_PATH_VAR="${CFG_PREFIX}/lib:$CFG_OLD_LD_PATH_VAR"
    "${CFG_PREFIX}/bin/${TEMPLATE_VERIFY_BIN}" --version > /dev/null
    if [ $? -ne 0 ]
    then
        ERR="can't execute installed binaries. "
        ERR="${ERR}installation may be broken. "
        ERR="${ERR}if this is expected then rerun install.sh with \`--disable-verify\` "
        ERR="${ERR}or \`make install\` with \`--disable-verify-install\`"
        err "${ERR}"
    else
        echo
        echo "    Note: please ensure '${CFG_PREFIX}/lib' is added to ${CFG_LD_PATH_VAR}"
    fi
fi

echo
echo "    ${TEMPLATE_SUCCESS_MESSAGE}"
echo


