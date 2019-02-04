// Copyright 2017 The Rust Project Developers. See the COPYRIGHT
// file at the top-level directory of this distribution and at
// http://rust-lang.org/COPYRIGHT.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.


use std::fs;
use std::path::Path;
use walkdir::WalkDir;

// Needed to set the script mode to executable.
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
// FIXME: what about Windows?  Are default ACLs executable?

#[cfg(unix)]
use std::os::unix::fs::symlink as symlink_file;
#[cfg(windows)]
use std::os::windows::fs::symlink_file;

use crate::errors::*;

/// Convert a `&Path` to a UTF-8 `&str`
pub fn path_to_str(path: &Path) -> Result<&str> {
    path.to_str().ok_or_else(|| {
        ErrorKind::Msg(format!("path is not valid UTF-8 '{}'", path.display())).into()
    })
}

/// Wrap `fs::copy` with a nicer error message
pub fn copy<P: AsRef<Path>, Q: AsRef<Path>>(from: P, to: Q) -> Result<u64> {
    if fs::symlink_metadata(&from)?.file_type().is_symlink() {
        let link = fs::read_link(&from)?;
        symlink_file(link, &to)?;
        Ok(0)
    } else {
        fs::copy(&from, &to)
            .chain_err(|| format!("failed to copy '{}' to '{}'",
                                  from.as_ref().display(), to.as_ref().display()))
    }
}

/// Wrap `fs::create_dir` with a nicer error message
pub fn create_dir<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::create_dir(&path)
        .chain_err(|| format!("failed to create dir '{}'", path.as_ref().display()))
}

/// Wrap `fs::create_dir_all` with a nicer error message
pub fn create_dir_all<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::create_dir_all(&path)
        .chain_err(|| format!("failed to create dir '{}'", path.as_ref().display()))
}

/// Wrap `fs::OpenOptions::create_new().open()` as executable, with a nicer error message
pub fn create_new_executable<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)] options.mode(0o755);
    options.open(&path)
        .chain_err(|| format!("failed to create file '{}'", path.as_ref().display()))
}

/// Wrap `fs::OpenOptions::create_new().open()`, with a nicer error message
pub fn create_new_file<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    fs::OpenOptions::new().write(true).create_new(true).open(&path)
        .chain_err(|| format!("failed to create file '{}'", path.as_ref().display()))
}

/// Wrap `fs::File::open()` with a nicer error message
pub fn open_file<P: AsRef<Path>>(path: P) -> Result<fs::File> {
    fs::File::open(&path)
        .chain_err(|| format!("failed to open file '{}'", path.as_ref().display()))
}

/// Wrap `remove_dir_all` with a nicer error message
pub fn remove_dir_all<P: AsRef<Path>>(path: P) -> Result<()> {
    crate::remove_dir_all::remove_dir_all(path.as_ref())
        .chain_err(|| format!("failed to remove dir '{}'", path.as_ref().display()))
}

/// Wrap `fs::remove_file` with a nicer error message
pub fn remove_file<P: AsRef<Path>>(path: P) -> Result<()> {
    fs::remove_file(path.as_ref())
        .chain_err(|| format!("failed to remove file '{}'", path.as_ref().display()))
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.
pub fn copy_recursive(src: &Path, dst: &Path) -> Result<()> {
    copy_with_callback(src, dst, |_, _| Ok(()))
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.  Invokes a callback for each path visited.
pub fn copy_with_callback<F>(src: &Path, dst: &Path, mut callback: F) -> Result<()>
    where F: FnMut(&Path, fs::FileType) -> Result<()>
{
    for entry in WalkDir::new(src).min_depth(1) {
        let entry = entry?;
        let file_type = entry.file_type();
        let path = entry.path().strip_prefix(src)?;
        let dst = dst.join(path);

        if file_type.is_dir() {
            create_dir(&dst)?;
        } else {
            copy(entry.path(), dst)?;
        }
        callback(&path, file_type)?;
    }
    Ok(())
}


/// Create an "actor" with default values and setters for all fields.
macro_rules! actor {
    ($( #[ $attr:meta ] )+ pub struct $name:ident {
        $( $( #[ $field_attr:meta ] )+ $field:ident : $type:ty = $default:expr, )*
    }) => {
        $( #[ $attr ] )+
        pub struct $name {
            $( $( #[ $field_attr ] )+ $field : $type, )*
        }

        impl Default for $name {
            fn default() -> Self {
                $name {
                    $( $field : $default.into(), )*
                }
            }
        }

        impl $name {
            $( $( #[ $field_attr ] )+
            pub fn $field<T: Into<$type>>(&mut self, value: T) -> &mut Self {
                self.$field = value.into();
                self
            })+
        }
    }
}
