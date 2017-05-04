// Copyright 2017 The Rust Project Developers. See the COPYRIGHT
// file at the top-level directory of this distribution and at
// http://rust-lang.org/COPYRIGHT.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

extern crate walkdir;

mod combiner;
mod generator;
mod scripter;
mod tarballer;
mod util;

pub use combiner::Combiner;
pub use generator::Generator;
pub use scripter::Scripter;
pub use tarballer::Tarballer;

/// The installer version, output only to be used by combine-installers.sh.
/// (should match `SOURCE_DIRECTORY/rust_installer_version`)
pub const RUST_INSTALLER_VERSION: u32 = 3;
