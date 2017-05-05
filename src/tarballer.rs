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
use std::io::{self, Seek, SeekFrom};
use std::path::Path;

use flate2;
use flate2::write::GzEncoder;
use tar::Builder;
use walkdir::WalkDir;
use xz2::write::XzEncoder;

actor!{
    #[derive(Debug)]
    pub struct Tarballer {
        /// The input folder to be compressed
        input: String = "package",

        /// The prefix of the tarballs
        output: String = "./dist",

        /// The fold in which the input is to be found
        work_dir: String = "./workdir",
    }
}

impl Tarballer {
    /// Generate the actual tarballs
    pub fn run(self) -> io::Result<()> {
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
        // let output = fs::File::create(&tar)?;
        let output = fs::OpenOptions::new().read(true).write(true).create_new(true).open(&tar)?;
        let mut builder = Builder::new(output);
        for path in paths {
            let path = Path::new(&path);
            let src = Path::new(&self.work_dir).join(path);
            if path.is_dir() {
                builder.append_dir(path, src)?;
            } else {
                let mut src = fs::File::open(src)?;
                builder.append_file(path, &mut src)?;
            }
        }
        let mut input = builder.into_inner()?;

        // Write the .tar.xz file
        let output = fs::File::create(&tar_xz)?;
        let mut encoded = XzEncoder::new(output, 9);
        input.seek(SeekFrom::Start(0))?;
        io::copy(&mut input, &mut encoded)?;
        encoded.finish()?;

        // Write the .tar.gz file
        let output = fs::File::create(&tar_gz)?;
        let mut encoded = GzEncoder::new(output, flate2::Compression::Best);
        input.seek(SeekFrom::Start(0))?;
        io::copy(&mut input, &mut encoded)?;
        encoded.finish()?;

        // Remove the .tar file
        drop(input);
        fs::remove_file(&tar)?;

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
