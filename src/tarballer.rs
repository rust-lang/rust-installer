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
use std::io::{self, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use walkdir::WalkDir;

use util::*;

#[derive(Debug)]
pub struct Tarballer {
    input: String,
    output: String,
    work_dir: String,
}

impl Default for Tarballer {
    fn default() -> Tarballer {
        Tarballer {
            input: "package".into(),
            output: "./dist".into(),
            work_dir: "./workdir.".into(),
        }
    }
}

impl Tarballer {
    /// The input folder to be compressed
    pub fn input(&mut self, value: String) -> &mut Self {
        self.input = value;
        self
    }

    /// The prefix of the tarballs
    pub fn output(&mut self, value: String) -> &mut Self {
        self.output = value;
        self
    }

    /// The fold in which the input is to be found
    pub fn work_dir(&mut self, value: String) -> &mut Self {
        self.work_dir = value;
        self
    }

    /// Generate the actual tarballs
    pub fn run(self) -> io::Result<()> {
        let path = get_path()?;
        need_cmd(&path, "tar")?;
        need_cmd(&path, "gzip")?;
        let have_xz = need_either_cmd(&path, "xz", "7z")?;

        let tar = self.output + ".tar";
        let tar_gz = tar.clone() + ".gz";
        let tar_xz = tar.clone() + ".xz";

        // Remove any existing files
        for file in &[&tar, &tar_gz, &tar_xz] {
            if Path::new(file).exists() {
                fs::remove_file(file)?;
            }
        }

        // Sort files by their suffix, to group files with the same name from
        // different locations (likely identical) and files with the same
        // extension (likely containing similar data).
        let mut paths = get_recursive_paths(self.work_dir.as_ref(), self.input.as_ref())?;
        paths.sort_by(|a, b| a.bytes().rev().cmp(b.bytes().rev()));

        // Write the tar file
        let mut child = Command::new("tar")
            .arg("-cf")
            .arg(&tar)
            .arg("-T")
            .arg("-")
            .stdin(Stdio::piped())
            .current_dir(&self.work_dir)
            .spawn()?;
        if let Some(stdin) = child.stdin.as_mut() {
            for path in paths {
                writeln!(stdin, "{}", path)?;
            }
        }
        let status = child.wait()?;
        if !status.success() {
            let msg = format!("failed to make tarball: {}", status);
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }

        // Write the .tar.xz file
        let status = if have_xz {
            Command::new("xz")
                .arg("-9")
                .arg("--keep")
                .arg(&tar)
                .status()?
        } else {
            Command::new("7z")
                .arg("a")
                .arg("-bd")
                .arg("-txz")
                .arg("-mx=9")
                .arg("-mmt=off")
                .arg(&tar_xz)
                .arg(&tar)
                .status()?
        };
        if !status.success() {
            let msg = format!("failed to make tar.xz: {}", status);
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }

        // Write the .tar.gz file (removing the .tar)
        let status = Command::new("gzip")
            .arg(&tar)
            .status()?;
        if !status.success() {
            let msg = format!("failed to make tar.gz: {}", status);
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }

        Ok(())
    }
}

fn get_recursive_paths(root: &Path, name: &Path) -> io::Result<Vec<String>> {
    let mut paths = vec![];
    for entry in WalkDir::new(root.join(name)).min_depth(1) {
        let entry = entry?;
        let path = entry.path().strip_prefix(root).unwrap();
        let path = path.to_str().unwrap().to_owned();

        if entry.file_type().is_dir() {
            // Include only empty dirs, as others get add via their contents.
            // FIXME: do we really need empty dirs at all?
            if fs::read_dir(entry.path())?.next().is_none() {
                paths.push(path);
            }
        } else {
            paths.push(path);
        }
    }
    Ok(paths)
}
