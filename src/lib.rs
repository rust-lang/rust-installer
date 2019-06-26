#[macro_use]
extern crate error_chain;

#[cfg(windows)]
extern crate winapi;
#[cfg(windows)]
#[macro_use]
extern crate lazy_static;

mod errors {
    error_chain! {
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

pub use crate::combiner::Combiner;
pub use crate::errors::{Error, ErrorKind, Result};
pub use crate::generator::Generator;
pub use crate::scripter::Scripter;
pub use crate::tarballer::Tarballer;

/// The installer version, output only to be used by combine-installers.sh.
/// (should match `SOURCE_DIRECTORY/rust_installer_version`)
pub const RUST_INSTALLER_VERSION: u32 = 3;
