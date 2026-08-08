//! Structured errors used by the native engine.

use std::fmt;
use std::io;
use std::path::PathBuf;

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InvalidImageReason {
    Truncated = 1,
    InvalidStructure = 2,
    DimensionsMissing = 3,
    ZeroDimensions = 4,
    AnimatedUnsupported = 5,
    InspectionLimitExceeded = 6,
}

impl fmt::Display for InvalidImageReason {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Truncated => "truncated image data",
            Self::InvalidStructure => "invalid image structure",
            Self::DimensionsMissing => "image dimensions not found",
            Self::ZeroDimensions => "image dimensions must be non-zero",
            Self::AnimatedUnsupported => "animated images are not supported",
            Self::InspectionLimitExceeded => "metadata exceeds inspection limit",
        };
        formatter.write_str(message)
    }
}

#[derive(Debug)]
pub enum Error {
    InputNotFound(PathBuf),
    InputNotFile(PathBuf),
    OutputParentMissing(PathBuf),
    OutputParentNotDirectory(PathBuf),
    OutputExists(PathBuf),
    InvalidManagedRoot(PathBuf),
    UnsupportedImageFormat(PathBuf),
    InvalidImage {
        path: PathBuf,
        reason: InvalidImageReason,
    },
    Io {
        operation: &'static str,
        path: PathBuf,
        source: io::Error,
    },
}

impl Error {
    pub(crate) fn io(operation: &'static str, path: impl Into<PathBuf>, source: io::Error) -> Self {
        Self::Io {
            operation,
            path: path.into(),
            source,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InputNotFound(path) => {
                write!(formatter, "input does not exist: {}", path.display())
            }
            Self::InputNotFile(path) => {
                write!(formatter, "input is not a regular file: {}", path.display())
            }
            Self::OutputParentMissing(path) => write!(
                formatter,
                "output directory does not exist: {}",
                path.display()
            ),
            Self::OutputParentNotDirectory(path) => write!(
                formatter,
                "output parent is not a directory: {}",
                path.display()
            ),
            Self::OutputExists(path) => {
                write!(formatter, "output already exists: {}", path.display())
            }
            Self::InvalidManagedRoot(path) => write!(
                formatter,
                "managed root is not a directory: {}",
                path.display()
            ),
            Self::UnsupportedImageFormat(path) => {
                write!(formatter, "unsupported image format: {}", path.display())
            }
            Self::InvalidImage { path, reason } => {
                write!(formatter, "invalid image {}: {reason}", path.display())
            }
            Self::Io {
                operation,
                path,
                source,
            } => write!(
                formatter,
                "{operation} failed for {}: {source}",
                path.display()
            ),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;
