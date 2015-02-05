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

# No undefined variables
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

absolutify() {
    local file_path="$1"
    local file_path_dirname="$(dirname "$file_path")"
    local file_path_basename="$(basename "$file_path")"
    local file_abs_path="$(cd "$file_path_dirname" && pwd)"
    local file_path="$file_abs_path/$file_path_basename"
    # This is the return value
    ABSOLUTIFIED="$file_path"
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
need_cmd chmod

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

flag uninstall "only uninstall from the installation prefix"
valopt destdir "" "set installation root"
opt verify 1 "verify that the installed binaries run correctly"
valopt prefix "/usr/local" "set installation prefix"
# NB This isn't quite the same definition as in `configure`.
# just using 'lib' instead of configure's CFG_LIBDIR_RELATIVE
valopt libdir "${CFG_DESTDIR}/${CFG_PREFIX}/lib" "install libraries"
valopt mandir "${CFG_DESTDIR}/${CFG_PREFIX}/share/man" "install man pages in PATH"
opt ldconfig 1 "run ldconfig after installation (Linux only)"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating arguments"
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

# This is where we are installing from
src_dir="$(cd $(dirname "$0") && pwd)"

# This is where we are installing to
dest_prefix="$CFG_DESTDIR/$CFG_PREFIX"

# Figure out what platform we're on for dealing with dynamic linker stuff
uname_value=$(uname -s)
case $uname_value in

    Linux)
        ostype=unknown-linux-gnu
        ;;

    FreeBSD)
        ostype=unknown-freebsd
        ;;

    DragonFly)
        ostype=unknown-dragonfly
        ;;

    Darwin)
        ostype=apple-darwin
        ;;

    MINGW*)
        ostype=pc-windows-gnu
        ;;

    MSYS*)
        ostype=pc-windows-gnu
        ;;

    # Vista 32 bit
    CYGWIN_NT-6.0)
        ostype=pc-windows-gnu
        ;;

    # Vista 64 bit
    CYGWIN_NT-6.0-WOW64)
        ostype=pc-windows-gnu
        ;;

    # Win 7 32 bit
    CYGWIN_NT-6.1)
        ostype=pc-windows-gnu
        ;;

    # Win 7 64 bit
    CYGWIN_NT-6.1-WOW64)
        ostype=pc-windows-gnu
        ;;

    *)
	err "unknown value from uname -s: $uname_value"
	;;
esac

# We'll need to know the env var for getting dynamic linking to work
# for verifying the bins
if [ "$ostype" = "pc-windows-gnu" ]
then
    ld_path_var=PATH
    old_ld_path_value="${PATH-}"
elif [ "$ostype" = "apple-darwin" ]
then
    ld_path_var=DYLD_LIBRARY_PATH
    old_ld_path_value="${DYLD_LIBRARY_PATH-}"
else
    ld_path_var=LD_LIBRARY_PATH
    old_ld_path_value="${LD_LIBRARY_PATH-}"
fi

# If we don't have a verify bin then disable verify
if [ -z "$TEMPLATE_VERIFY_BIN" ]; then
    CFG_DISABLE_VERIFY=1
fi

# Sanity check: can we run the binaries?
if [ -z "${CFG_DISABLE_VERIFY-}" ]
then
    # Don't do this if uninstalling. Failure here won't help in any way.
    if [ -z "${CFG_UNINSTALL-}" ]
    then
        msg "verifying platform can run binaries"
        export $ld_path_var="${src_dir}/lib:$old_ld_path_value"
        "${src_dir}/bin/${TEMPLATE_VERIFY_BIN}" --version 2> /dev/null 1> /dev/null
        if [ $? -ne 0 ]
        then
            err "can't execute binaries on this platform"
        fi
        export $ld_path_var="$old_ld_path_value"
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
prefix_dir="$(cd "$dest_prefix" && pwd)"
if [ "$src_dir" = "$prefix_dir" ]
then
    err "can't install to same directory as installer"
fi

# Open the components file to get the list of components to install
components=`cat "$src_dir/components"`

# Sanity check: do we have components?
if [ ! -n "$components" ]; then
    err "unable to find installation components"
fi

# Using an absolute path to libdir in a few places so that the status
# messages are consistently using absolute paths.
absolutify "$CFG_LIBDIR"
abs_libdir="$ABSOLUTIFIED"

# We're going to start by uninstalling existing components. This
uninstalled_something=false

# Replace commas in legacy manifest list with spaces
legacy_manifest_dirs=`echo "$TEMPLATE_LEGACY_MANIFEST_DIRS" | sed "s/,/ /g"`

# Uninstall from legacy manifests
for md in $legacy_manifest_dirs; do
    # First, uninstall from the installation prefix.
    # Errors are warnings - try to rm everything in the manifest even if some fail.
    if [ -f "$abs_libdir/$md/manifest" ]
    then

	# iterate through installed manifest and remove files
	while read p; do
            # the installed manifest contains absolute paths
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
	done < "$abs_libdir/$md/manifest"

	# If we fail to remove $md below, then the
	# installed manifest will still be full; the installed manifest
	# needs to be empty before install.
	msg "removing legacy manifest $abs_libdir/$md/manifest"
	rm -f "$abs_libdir/$md/manifest"
	# For the above reason, this is a hard error
	need_ok "failed to remove installed manifest"

	# Remove $template_rel_manifest_dir directory
	msg "removing legacy manifest dir $abs_libdir/$md"
	rm -Rf "$abs_libdir/$md"
	if [ $? -ne 0 ]
	then
            warn "failed to remove $md"
	fi

	uninstalled_something=true
    fi
done

# Load the version of the installed installer
installed_version=
if [ -f "$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version" ]; then
    installed_version=`cat "$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version"`

    # Sanity check
    if [ ! -n "$installed_version" ]; then err "rust installer version is empty"; fi
fi

# If there's something installed, then uninstall
if [ -n "$installed_version" ]; then
    # Check the version of the installed installer
    case "$installed_version" in

	# TODO: If this is a previous version, then upgrade in place to the
	# current version before uninstalling. No need to do this yet because
	# there is no prior version (only the legacy 'unversioned' installer
	# which we've already dealt with).

	# This is the current version. Nothing need to be done except uninstall.
	"$TEMPLATE_RUST_INSTALLER_VERSION")
	    ;;

	# TODO: If this is an unknown (future) version then bail.
	*)
	    echo "The copy of $TEMPLATE_PRODUCT_NAME at $dest_prefix was installed using an"
	    echo "unknown version ($installed_version) of rust-installer."
	    echo "Uninstall it first with the installer used for the original installation"
	    echo "before continuing."
	    exit 1
	    ;;
    esac

    md="$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR"
    installed_components=`cat $md/components`

    # Uninstall (our components only) before reinstalling
    for available_component in $components; do
	for installed_component in $installed_components; do
	    if [ "$available_component" = "$installed_component" ]; then
		component_manifest="$md/manifest-$installed_component"

		# Sanity check: there should be a component manifest
		if [ ! -f "$component_manifest" ]; then
		    err "installed component '$installed_component' has no manifest"
		fi

		# Iterate through installed component manifest and remove files
		while read directive; do

		    command=`echo $directive | cut -f1 -d:`
		    file=`echo $directive | cut -f2 -d:`

		    # Sanity checks
		    if [ ! -n "$command" ]; then err "malformed installation directive"; fi
		    if [ ! -n "$file" ]; then err "malformed installation directive"; fi

		    case "$command" in
			file)
			    msg "removing file $file"
			    if [ -f "$file" ]; then
				rm -f "$file"
				if [ $? -ne 0 ]; then
				    warn "failed to remove $file"
				fi
			    else
				warn "supposedly installed file $file does not exist!"
			    fi
			    ;;

			dir)
			    msg "removing directory $file"
			    rm -rf "$file"
			    if [ $? -ne 0 ]; then
				warn "unable to remove directory $file"
			    fi
			    ;;

			*)
			    err "unknown installation directive"
			    ;;
		    esac

		done < "$component_manifest"

		# Remove the installed component manifest
		msg "removing component manifest $component_manifest"
		rm -f "$component_manifest"
		# This is a hard error because the installation is unrecoverable
		need_ok "failed to remove installed manifest for component '$installed_component'"

		# Update the installed component list
		modified_components=`sed /^$installed_component\$/d $md/components`
		echo "$modified_components" > "$md/components"
		need_ok "failed to update installed component list"
	    fi
	done
    done

    # If there are no remaining components delete the manifest directory
    remaining_components=`cat $md/components`
    if [ ! -n "$remaining_components" ]; then
	msg "removing manifest directory $md"
	rm -rf "$md"
	if [ $? -ne 0 ]; then
	    warn "failed to remove $md"
	fi
    fi

    uninstalled_something=true
fi

# There's no installed version. If we were asked to uninstall, then that's a problem.
if [ -n "${CFG_UNINSTALL-}" -a "$uninstalled_something" = false ]
then
    err "unable to find installation manifest at $CFG_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"
fi

# If we're only uninstalling then exit
if [ -n "${CFG_UNINSTALL-}" ]
then
    echo
    echo "    $TEMPLATE_PRODUCT_NAME is uninstalled."
    echo
    exit 0
fi

# Create the directory to contain the manifests
mkdir -p "$CFG_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"
need_ok "failed to create $TEMPLATE_REL_MANIFEST_DIR"

# Install each component
for component in $components; do

    # The file name of the manifest we're installing from
    input_manifest="$src_dir/manifest-$component.in"

    # The installed manifest directory
    md="$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR"

    # The file name of the manifest we're going to create during install
    installed_manifest="$md/manifest-$component"

    # Create the installed manifest, which we will fill in with absolute file paths
    touch "$installed_manifest"
    need_ok "failed to create installed manifest"

    # Sanity check: do we have our input manifests?
    if [ ! -f "$input_manifest" ]; then
	err "manifest for $component does not exist at $input_manifest"
    fi

    # Now install, iterate through the new manifest and copy files
    while read directive; do

	command=`echo $directive | cut -f1 -d:`
	file=`echo $directive | cut -f2 -d:`

	# Sanity checks
	if [ ! -n "$command" ]; then err "malformed installation directive"; fi
	if [ ! -n "$file" ]; then err "malformed installation directive"; fi

	# Decide the destination of the file
	file_install_path="$dest_prefix/$file"

	if echo "$file" | grep "^lib/" > /dev/null
	then
            f=`echo $file | sed 's/^lib\///'`
            file_install_path="$CFG_LIBDIR/$f"
	fi

	if echo "$file" | grep "^share/man/" > /dev/null
	then
            f=`echo $file | sed 's/^share\/man\///'`
            file_install_path="$CFG_MANDIR/$f"
	fi

	# Make sure there's a directory for it
	umask 022 && mkdir -p "$(dirname "$file_install_path")"
	need_ok "directory creation failed"

	# Make the path absolute so we can uninstall it later without
	# starting from the installation cwd
	absolutify "$file_install_path"
	file_install_path="$ABSOLUTIFIED"

	case "$command" in
	    file)

		# Install the file
		msg "copying file $file_install_path"
		if echo "$file" | grep "^bin/" > /dev/null
		then
		    install -m755 "$src_dir/$file" "$file_install_path"
		else
		    install -m644 "$src_dir/$file" "$file_install_path"
		fi
		need_ok "file creation failed"

		# Update the manifest
		echo "file:$file_install_path" >> "$installed_manifest"
		need_ok "failed to update manifest"

		;;

	    dir)

		# Copy the dir
		msg "copying directory $file_install_path"

		# Sanity check: bulk dirs are supposed to be uniquely ours and should not exist
		if [ -e "$file_install_path" ]; then
		    err "$file_install_path already exists"
		fi

		cp -R "$src_dir/$file" "$file_install_path"
		need_ok "failed to copy directory"

                # Set permissions. 0755 for dirs, 644 for files
                chmod -R u+rwx,go+rx,go-w "$file_install_path"
                need_ok "failed to set permissions on directory"

		# Update the manifest
		echo "dir:$file_install_path" >> "$installed_manifest"
		need_ok "failed to update manifest"
		;;

	    *)
		err "unknown installation directive"
		;;
	esac
    done < "$input_manifest"

    # Update the components
    echo "$component" >> "$md/components"
    need_ok "failed to update components list for $component"

done

# Drop the version number into the manifest dir
echo "$TEMPLATE_RUST_INSTALLER_VERSION" > "$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version"

# Run ldconfig to make dynamic libraries available to the linker
if [ "$ostype" = "unknown-linux-gnu" -a ! -n "${CFG_DISABLE_LDCONFIG-}" ]; then
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
# is in place.
if [ -z "${CFG_DISABLE_VERIFY-}" ]
then
    export $ld_path_var="$dest_prefix/lib:$old_ld_path_value"
    "$dest_prefix/bin/$TEMPLATE_VERIFY_BIN" --version > /dev/null
    if [ $? -ne 0 ]
    then
        err="can't execute installed binaries. "
        err="${err}installation may be broken. "
        err="${err}if this is expected then rerun install.sh with \`--disable-verify\` "
        err="${err}or \`make install\` with \`--disable-verify-install\`"
        err "${err}"
    else
        echo
        echo "    note: please ensure '$dest_prefix/lib' is added to ${ld_path_var}"
    fi
fi

echo
echo "    $TEMPLATE_SUCCESS_MESSAGE"
echo


