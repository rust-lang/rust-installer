// Copyright 2017 The Rust Project Developers. See the COPYRIGHT
// file at the top-level directory of this distribution and at
// http://rust-lang.org/COPYRIGHT.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#[macro_use]
extern crate error_chain;

#[cfg(windows)]
extern crate winapi;
#[cfg(windows)]
#[macro_use]
extern crate lazy_static;

mod errors {
    error_chain!{
        foreign_links {
            Io(::std::io::Error);
            StripPrefix(::std::path::StripPrefixError);
            WalkDir(::walkdir::Error);
        }
    }
}

#[macro_use]
mod util;

// deal with OS complications (cribbed from rustup.rs)
mod remove_dir_all;

mod combiner;
mod generator;
mod scripter;
mod tarballer;

pub use crate::errors::{Result, Error, ErrorKind};
pub use crate::combiner::Combiner;
pub use crate::generator::Generator;
pub use crate::scripter::Scripter;
pub use crate::tarballer::Tarballer;

/// The installer version, output only to be used by combine-installers.sh.
/// (should match `SOURCE_DIRECTORY/rust_installer_version`)
pub const RUST_INSTALLER_VERSION: u32 = 3;
