//! File lifecycle primitives. Image decoding is intentionally kept separate.

mod cleanup;
mod input;
mod naming;
mod output;
mod staging;

pub use cleanup::{CleanupReport, cleanup_managed_files};
pub use input::open_input;
pub use output::{OutputFileType, OutputTarget};
pub use staging::StagedOutput;
