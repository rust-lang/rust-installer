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
use std::io;
use std::path::Path;
use walkdir::WalkDir;

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
