use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) const OWNED_PREFIX: &str = "fic_";
static SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn unique_token() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("{nanos:x}_{:x}_{sequence:x}", std::process::id())
}

pub(crate) fn managed_path(directory: &Path, extension: &str) -> PathBuf {
    directory.join(format!(
        "{OWNED_PREFIX}output_{}.{}",
        unique_token(),
        extension
    ))
}

pub(crate) fn staging_path(final_path: &Path) -> PathBuf {
    let directory = final_path.parent().unwrap_or_else(|| Path::new("."));
    directory.join(format!("{OWNED_PREFIX}staging_{}.tmp", unique_token()))
}

pub(crate) fn is_owned_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with(OWNED_PREFIX))
}
