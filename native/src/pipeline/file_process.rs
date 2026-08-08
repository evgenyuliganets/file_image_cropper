use std::fmt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crate::codecs::jpeg::{self, JpegCodecError};
use crate::codecs::png::{self, PngCodecError};
use crate::codecs::webp::{self, WebPCodecError};
use crate::crop::{AspectMismatchPolicy, CropRegion, resolve_crop_region};
use crate::error::Error;
use crate::filesystem::{OutputFileType, OutputTarget, StagedOutput, open_input};
use crate::image_info::{ImageFormat, inspect_path};
use crate::pixel::{PixelError, PixelLimits};
use crate::resize::ResizeFilter;
use crate::rotate::{Orientation, oriented_dimensions};

use super::{PixelProcessRequest, ResizeSpec, process_pixels_shared};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OutputCodec {
    Png,
    Jpeg { quality: u8, background: [u8; 3] },
    WebP { lossless: bool, quality: u8 },
}

impl OutputCodec {
    pub fn file_type(self) -> OutputFileType {
        match self {
            Self::Png => OutputFileType::Png,
            Self::Jpeg { .. } => OutputFileType::Jpeg,
            Self::WebP { .. } => OutputFileType::WebP,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FileCropRequest {
    pub region: CropRegion,
    pub output_size: Option<(u32, u32)>,
    pub aspect_mismatch_policy: AspectMismatchPolicy,
    pub resize_filter: ResizeFilter,
    pub limits: PixelLimits,
    pub output_codec: OutputCodec,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileProcessResult {
    pub path: PathBuf,
    pub is_managed: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct FileProcessTimings {
    pub inspect: Duration,
    pub open: Duration,
    pub decode: Duration,
    pub pixels: Duration,
    pub staging: Duration,
    pub encode: Duration,
    pub commit: Duration,
}

impl FileProcessTimings {
    pub fn total(self) -> Duration {
        self.inspect
            + self.open
            + self.decode
            + self.pixels
            + self.staging
            + self.encode
            + self.commit
    }
}

#[derive(Debug)]
pub enum CodecError {
    Png(PngCodecError),
    Jpeg(JpegCodecError),
    WebP(WebPCodecError),
}

impl fmt::Display for CodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Png(error) => error.fmt(formatter),
            Self::Jpeg(error) => error.fmt(formatter),
            Self::WebP(error) => error.fmt(formatter),
        }
    }
}

#[derive(Debug)]
pub enum FileProcessError {
    Input(Error),
    Output(Error),
    Decode(CodecError),
    Encode(CodecError),
    Pixels(PixelError),
}

impl fmt::Display for FileProcessError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Input(error) | Self::Output(error) => error.fmt(formatter),
            Self::Decode(error) => write!(formatter, "image decode failed: {error}"),
            Self::Encode(error) => write!(formatter, "image encode failed: {error}"),
            Self::Pixels(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for FileProcessError {}

impl From<PixelError> for FileProcessError {
    fn from(error: PixelError) -> Self {
        Self::Pixels(error)
    }
}

pub fn process_image_file(
    input_path: &Path,
    output_target: OutputTarget,
    request: FileCropRequest,
) -> Result<FileProcessResult, FileProcessError> {
    process_image_file_profiled(input_path, output_target, request).map(|(result, _)| result)
}

pub fn process_image_file_profiled(
    input_path: &Path,
    output_target: OutputTarget,
    request: FileCropRequest,
) -> Result<(FileProcessResult, FileProcessTimings), FileProcessError> {
    let mut timings = FileProcessTimings::default();
    let mut started = Instant::now();
    let metadata = inspect_path(input_path).map_err(FileProcessError::Input)?;
    let orientation = Orientation::try_from(metadata.orientation)?;
    let (oriented_width, oriented_height) =
        oriented_dimensions(metadata.width, metadata.height, orientation);
    let crop = resolve_crop_region(
        request.region,
        oriented_width,
        oriented_height,
        request.output_size,
        request.aspect_mismatch_policy,
    )?;
    timings.inspect = started.elapsed();
    started = Instant::now();
    let input = open_input(input_path).map_err(FileProcessError::Input)?;
    timings.open = started.elapsed();
    started = Instant::now();
    let decoded = match metadata.format {
        ImageFormat::Png => png::decode(input, request.limits)
            .map_err(|error| FileProcessError::Decode(CodecError::Png(error)))?,
        ImageFormat::Jpeg => jpeg::decode(input, request.limits)
            .map_err(|error| FileProcessError::Decode(CodecError::Jpeg(error)))?,
        ImageFormat::WebP => webp::decode(input, request.limits)
            .map_err(|error| FileProcessError::Decode(CodecError::WebP(error)))?,
    };
    timings.decode = started.elapsed();
    started = Instant::now();
    let processed = process_pixels_shared(
        decoded,
        PixelProcessRequest {
            orientation,
            crop: Some(crop),
            resize: request.output_size.map(|(width, height)| ResizeSpec {
                width,
                height,
                filter: request.resize_filter,
            }),
            limits: request.limits,
        },
    )?;
    timings.pixels = started.elapsed();
    started = Instant::now();
    let is_managed = output_target.is_managed();
    let mut staged = StagedOutput::create(output_target).map_err(FileProcessError::Output)?;
    timings.staging = started.elapsed();
    started = Instant::now();
    match request.output_codec {
        OutputCodec::Png => png::encode(staged.writer(), &processed)
            .map_err(|error| FileProcessError::Encode(CodecError::Png(error)))?,
        OutputCodec::Jpeg {
            quality,
            background,
        } => jpeg::encode(staged.writer(), &processed, quality, background)
            .map_err(|error| FileProcessError::Encode(CodecError::Jpeg(error)))?,
        OutputCodec::WebP { lossless, quality } => {
            webp::encode(staged.writer(), &processed, lossless, quality)
                .map_err(|error| FileProcessError::Encode(CodecError::WebP(error)))?
        }
    }
    timings.encode = started.elapsed();
    started = Instant::now();
    let path = staged.commit().map_err(FileProcessError::Output)?;
    timings.commit = started.elapsed();
    Ok((FileProcessResult { path, is_managed }, timings))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codecs::jpeg::{DEFAULT_BACKGROUND, DEFAULT_QUALITY};
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn png_fixture() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/png/pngtest.png")
    }

    fn jpeg_fixture() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/jpeg/Portrait_6.jpg")
    }

    fn webp_fixture() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/webp/test.webp")
    }

    fn temp_directory(label: &str) -> PathBuf {
        let token = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "file_image_cropper_{label}_{}_{token}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        path
    }

    fn request(output_codec: OutputCodec) -> FileCropRequest {
        FileCropRequest {
            region: CropRegion::Pixels(crate::crop::CropRect {
                x: 1,
                y: 2,
                width: 40,
                height: 30,
            }),
            output_size: Some((20, 15)),
            aspect_mismatch_policy: AspectMismatchPolicy::Reject,
            resize_filter: ResizeFilter::Bilinear,
            limits: PixelLimits::default(),
            output_codec,
        }
    }

    #[test]
    fn processes_real_png_without_modifying_input() {
        let input = png_fixture();
        let original = fs::read(&input).unwrap();
        let directory = temp_directory("png_e2e");
        let output = directory.join("result.png");
        let result = process_image_file(
            &input,
            OutputTarget::explicit(&output, false).unwrap(),
            request(OutputCodec::Png),
        )
        .unwrap();
        assert_eq!(result.path, output);
        let decoded =
            png::decode(open_input(&result.path).unwrap(), PixelLimits::default()).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (20, 15));
        assert_eq!(fs::read(input).unwrap(), original);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn normalizes_exif_orientation_and_creates_managed_jpeg() {
        let directory = temp_directory("jpeg_managed");
        let target = OutputTarget::managed(&directory, OutputFileType::Jpeg).unwrap();
        let result = process_image_file(
            &jpeg_fixture(),
            target,
            request(OutputCodec::Jpeg {
                quality: DEFAULT_QUALITY,
                background: DEFAULT_BACKGROUND,
            }),
        )
        .unwrap();
        let info = inspect_path(&result.path).unwrap();
        assert!(result.is_managed);
        assert_eq!((info.width, info.height, info.orientation), (20, 15, 1));
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn converts_png_to_jpeg() {
        let directory = temp_directory("png_to_jpeg");
        let target = OutputTarget::explicit(directory.join("result.jpg"), false).unwrap();
        let result = process_image_file(
            &png_fixture(),
            target,
            request(OutputCodec::Jpeg {
                quality: 95,
                background: [255, 255, 255],
            }),
        )
        .unwrap();
        assert_eq!(
            inspect_path(&result.path).unwrap().format,
            ImageFormat::Jpeg
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn processes_real_webp_input() {
        let input = webp_fixture();
        let original = fs::read(&input).unwrap();
        let directory = temp_directory("webp_input");
        let target = OutputTarget::explicit(directory.join("result.png"), false).unwrap();
        let result = process_image_file(&input, target, request(OutputCodec::Png)).unwrap();
        assert_eq!(inspect_path(&result.path).unwrap().format, ImageFormat::Png);
        assert_eq!(fs::read(input).unwrap(), original);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn creates_managed_lossy_webp() {
        let directory = temp_directory("webp_managed");
        let target = OutputTarget::managed(&directory, OutputFileType::WebP).unwrap();
        let result = process_image_file(
            &png_fixture(),
            target,
            request(OutputCodec::WebP {
                lossless: false,
                quality: 82,
            }),
        )
        .unwrap();
        let info = inspect_path(&result.path).unwrap();
        assert!(result.is_managed);
        assert_eq!(
            (info.width, info.height, info.format),
            (20, 15, ImageFormat::WebP)
        );
        fs::remove_dir_all(directory).unwrap();
    }
}
