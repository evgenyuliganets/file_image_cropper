use std::path::PathBuf;

use file_image_cropper_native::image_info::{ImageFormat, inspect_path};

fn fixture(relative: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join(relative)
}

#[test]
fn reads_all_real_jpeg_exif_orientations() {
    for orientation in 1..=8 {
        let path = fixture(&format!("jpeg/Portrait_{orientation}.jpg"));
        let info = inspect_path(&path).unwrap();
        assert_eq!(info.format, ImageFormat::Jpeg, "{}", path.display());
        assert_eq!(info.orientation, orientation, "{}", path.display());
        assert!(info.width > 0 && info.height > 0);
    }
}

#[test]
fn reads_real_upstream_png() {
    let info = inspect_path(&fixture("png/pngtest.png")).unwrap();
    assert_eq!(info.format, ImageFormat::Png);
    assert_eq!((info.width, info.height), (91, 69));
}

#[test]
fn reads_real_upstream_webp() {
    let info = inspect_path(&fixture("webp/test.webp")).unwrap();
    assert_eq!(info.format, ImageFormat::WebP);
    assert!(info.width > 0 && info.height > 0);
}
