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
        let tar_gz = self.output.clone() + ".tar.gz";
        let tar_xz = self.output.clone() + ".tar.xz";

        // Remove any existing files
        for file in &[&tar_gz, &tar_xz] {
            if Path::new(file).exists() {
                fs::remove_file(file)?;
            }
        }

        // Sort files by their suffix, to group files with the same name from
        // different locations (likely identical) and files with the same
        // extension (likely containing similar data).
        let mut paths = get_recursive_paths(self.work_dir.as_ref(), self.input.as_ref())?;
        paths.sort_by(|a, b| a.bytes().rev().cmp(b.bytes().rev()));

        // Prepare the .tar.gz file
        let output = fs::File::create(&tar_gz)?;
        let gz = GzEncoder::new(output, flate2::Compression::Best);

        // Prepare the .tar.xz file
        let output = fs::File::create(&tar_xz)?;
        let xz = XzEncoder::new(output, 9);

        // Write the tar into both encoded files
        let mut builder = Builder::new(Tee(gz, xz));
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
        let Tee(gz, xz) = builder.into_inner()?;

        // Finish both encoded files
        gz.finish()?;
        xz.finish()?;

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

struct Tee<A, B>(A, B);

impl<A: Write, B: Write> Write for Tee<A, B> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.write_all(buf)
            .and(self.1.write_all(buf))
            .and(Ok(buf.len()))
    }

    fn flush(&mut self) -> io::Result<()> {
        self.0.flush().and(self.1.flush())
    }
}
