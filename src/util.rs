// Copyright 2017 The Rust Project Developers. See the COPYRIGHT
// file at the top-level directory of this distribution and at
// http://rust-lang.org/COPYRIGHT.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

use std::env;
use std::ffi::{OsString, OsStr};
use std::fs;
use std::io;
use std::path::Path;
use walkdir::WalkDir;

pub fn get_path() -> io::Result<OsString> {
    let path = env::var_os("PATH").unwrap_or(OsString::new());
    // On Windows, quotes are invalid characters for filename paths, and if
    // one is present as part of the PATH then that can lead to the system
    // being unable to identify the files properly. See
    // https://github.com/rust-lang/rust/issues/34959 for more details.
    if cfg!(windows) {
        if path.to_string_lossy().contains("\"") {
            let msg = "PATH contains invalid character '\"'";
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }
    }
    Ok(path)
}

pub fn have_cmd(path: &OsStr, cmd: &str) -> bool {
    for path in env::split_paths(path) {
        let target = path.join(cmd);
        let cmd_alt = cmd.to_string() + ".exe";
        if target.is_file() ||
           target.with_extension("exe").exists() ||
           target.join(cmd_alt).exists() {
            return true;
        }
    }
    false
}

pub fn need_cmd(path: &OsStr, cmd: &str) -> io::Result<()> {
    if have_cmd(path, cmd) {
        Ok(())
    } else {
        let msg = format!("couldn't find required command: '{}'", cmd);
        Err(io::Error::new(io::ErrorKind::NotFound, msg))
    }
}

pub fn need_either_cmd(path: &OsStr, cmd1: &str, cmd2: &str) -> io::Result<bool> {
    if have_cmd(path, cmd1) {
        Ok(true)
    } else if have_cmd(path, cmd2) {
        Ok(false)
    } else {
        let msg = format!("couldn't find either command: '{}' or '{}'", cmd1, cmd2);
        Err(io::Error::new(io::ErrorKind::NotFound, msg))
    }
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.
pub fn copy_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    copy_with_callback(src, dst, |_, _| Ok(()))
}

/// Copies the `src` directory recursively to `dst`. Both are assumed to exist
/// when this function is called.  Invokes a callback for each path visited.
pub fn copy_with_callback<F>(src: &Path, dst: &Path, mut callback: F) -> io::Result<()>
    where F: FnMut(&Path, fs::FileType) -> io::Result<()>
{
    for entry in WalkDir::new(src).min_depth(1) {
        let entry = entry?;
        let file_type = entry.file_type();
        let path = entry.path().strip_prefix(src).unwrap();
        let dst = dst.join(path);

        if file_type.is_dir() {
            fs::create_dir(&dst)?;
        } else {
            fs::copy(entry.path(), dst)?;
        }
        callback(&path, file_type)?;
    }
    Ok(())
}
