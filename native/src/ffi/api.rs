//! C ABI metadata operations. The package build hook will link these exports
//! once Cargo integration is enabled.

use std::path::Path;

use crate::crop::{AspectMismatchPolicy, CropRect, CropRegion};
use crate::error::Error;
use crate::filesystem::OutputTarget;
use crate::image_info::{self, ImageFormat};
use crate::pipeline::{
    CodecError, FileCropRequest, FileProcessError, OutputCodec, process_image_file,
    process_rgba_view_file,
};
use crate::pixel::{PixelError, PixelLimits, PixelView};
use crate::resize::ResizeFilter;

/// Native ABI generation used by platform bridges to force the bundled code
/// asset to load before resolving optional symbols.
#[unsafe(no_mangle)]
pub extern "C" fn file_image_cropper_abi_version() -> u32 {
    3
}

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImageInfoStatus {
    Ok = 0,
    InvalidPathEncoding = 1,
    InputNotFound = 2,
    InputNotFile = 3,
    UnsupportedFormat = 4,
    InvalidImage = 5,
    Io = 6,
    Panic = 255,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FfiImageInfoResult {
    pub status: i32,
    pub reason: u32,
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub orientation: u8,
    pub _reserved: [u8; 3],
}

impl FfiImageInfoResult {
    fn failure(status: ImageInfoStatus, reason: u32) -> Self {
        Self {
            status: status as i32,
            reason,
            width: 0,
            height: 0,
            format: 0,
            orientation: 0,
            _reserved: [0; 3],
        }
    }
}

/// Inspects the image at a UTF-8 path. The byte slice is borrowed only for the
/// duration of this call and no native allocation crosses the ABI boundary.
///
/// # Safety
/// When `path_length` is non-zero, `path_bytes` must point to a readable byte
/// region of at least `path_length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn file_image_cropper_inspect_image(
    path_bytes: *const u8,
    path_length: usize,
) -> FfiImageInfoResult {
    std::panic::catch_unwind(|| {
        if path_bytes.is_null() && path_length != 0 {
            return FfiImageInfoResult::failure(ImageInfoStatus::InvalidPathEncoding, 0);
        }
        let bytes = if path_length == 0 {
            &[]
        } else {
            // SAFETY: Guaranteed by the function's caller contract.
            unsafe { std::slice::from_raw_parts(path_bytes, path_length) }
        };
        let path = match std::str::from_utf8(bytes) {
            Ok(path) => Path::new(path),
            Err(_) => {
                return FfiImageInfoResult::failure(ImageInfoStatus::InvalidPathEncoding, 0);
            }
        };
        match image_info::inspect_path(path) {
            Ok(info) => FfiImageInfoResult {
                status: ImageInfoStatus::Ok as i32,
                reason: 0,
                width: info.width,
                height: info.height,
                format: match info.format {
                    ImageFormat::Jpeg => 1,
                    ImageFormat::Png => 2,
                    ImageFormat::WebP => 3,
                },
                orientation: info.orientation,
                _reserved: [0; 3],
            },
            Err(error) => {
                let (status, reason) = status_for_error(&error);
                FfiImageInfoResult::failure(status, reason)
            }
        }
    })
    .unwrap_or_else(|_| FfiImageInfoResult::failure(ImageInfoStatus::Panic, 0))
}

fn status_for_error(error: &Error) -> (ImageInfoStatus, u32) {
    match error {
        Error::InputNotFound(_) => (ImageInfoStatus::InputNotFound, 0),
        Error::InputNotFile(_) => (ImageInfoStatus::InputNotFile, 0),
        Error::UnsupportedImageFormat(_) => (ImageInfoStatus::UnsupportedFormat, 0),
        Error::InvalidImage { reason, .. } => (ImageInfoStatus::InvalidImage, *reason as u32),
        Error::Io { .. } => (ImageInfoStatus::Io, 0),
        _ => (ImageInfoStatus::Io, 0),
    }
}

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CropStatus {
    Ok = 0,
    InvalidPath = 1,
    Input = 2,
    UnsupportedFormat = 3,
    Decode = 4,
    InvalidRequest = 5,
    Output = 6,
    Encode = 7,
    ResultPathTooLong = 8,
    Panic = 255,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FfiCropResult {
    pub status: i32,
    pub reason: u32,
    pub path_length: usize,
    pub is_managed: u8,
    pub _reserved: [u8; 7],
}

impl FfiCropResult {
    fn failure(status: CropStatus, reason: u32) -> Self {
        Self {
            status: status as i32,
            reason,
            path_length: 0,
            is_managed: 0,
            _reserved: [0; 7],
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FfiCropOptions {
    pub region_type: u32,
    pub aspect_policy: u32,
    pub region_a: f64,
    pub region_b: f64,
    pub region_c: f64,
    pub region_d: f64,
    pub output_width: u32,
    pub output_height: u32,
    pub resize_filter: u32,
    pub output_format: u32,
    pub jpeg_quality: u32,
    pub jpeg_background_red: u32,
    pub jpeg_background_green: u32,
    pub jpeg_background_blue: u32,
    pub webp_lossless: u32,
    pub webp_quality: u32,
    pub overwrite: u32,
}

/// Executes the end-to-end file crop pipeline for the currently supported codecs.
///
/// # Safety
/// Every non-null pointer must reference a readable region matching its length;
/// `options` must point to a readable `FfiCropOptions`, and `result_path` must
/// reference a writable region of `result_path_capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn file_image_cropper_crop_image(
    input_bytes: *const u8,
    input_length: usize,
    output_bytes: *const u8,
    output_length: usize,
    managed_root_bytes: *const u8,
    managed_root_length: usize,
    options: *const FfiCropOptions,
    result_path: *mut u8,
    result_path_capacity: usize,
) -> FfiCropResult {
    std::panic::catch_unwind(|| {
        let input = match unsafe { utf8_path(input_bytes, input_length) } {
            Some(path) => path,
            None => return FfiCropResult::failure(CropStatus::InvalidPath, 0),
        };
        if options.is_null() {
            return FfiCropResult::failure(CropStatus::InvalidRequest, 0);
        }
        // SAFETY: Guaranteed by the function's caller contract.
        let options = unsafe { *options };
        let Some(region) = crop_region(&options) else {
            return FfiCropResult::failure(CropStatus::InvalidRequest, 0);
        };
        let aspect_mismatch_policy = match options.aspect_policy {
            0 => AspectMismatchPolicy::Reject,
            1 => AspectMismatchPolicy::AdjustCrop,
            2 => AspectMismatchPolicy::Stretch,
            _ => return FfiCropResult::failure(CropStatus::InvalidRequest, 0),
        };
        let output_codec = match options.output_format {
            0 if (1..=100).contains(&options.jpeg_quality)
                && options.jpeg_background_red <= u8::MAX as u32
                && options.jpeg_background_green <= u8::MAX as u32
                && options.jpeg_background_blue <= u8::MAX as u32 =>
            {
                OutputCodec::Jpeg {
                    quality: options.jpeg_quality as u8,
                    background: [
                        options.jpeg_background_red as u8,
                        options.jpeg_background_green as u8,
                        options.jpeg_background_blue as u8,
                    ],
                }
            }
            1 => OutputCodec::Png,
            2 if options.webp_quality <= 100 && options.webp_lossless <= 1 => OutputCodec::WebP {
                lossless: options.webp_lossless != 0,
                quality: options.webp_quality as u8,
            },
            0 | 2 => return FfiCropResult::failure(CropStatus::InvalidRequest, 0),
            _ => return FfiCropResult::failure(CropStatus::UnsupportedFormat, 0),
        };
        let target = if output_length == 0 {
            let Some(root) = (unsafe { utf8_path(managed_root_bytes, managed_root_length) }) else {
                return FfiCropResult::failure(CropStatus::InvalidPath, 0);
            };
            match OutputTarget::managed(root, output_codec.file_type()) {
                Ok(target) => target,
                Err(_) => return FfiCropResult::failure(CropStatus::Output, 0),
            }
        } else {
            let Some(output) = (unsafe { utf8_path(output_bytes, output_length) }) else {
                return FfiCropResult::failure(CropStatus::InvalidPath, 0);
            };
            match OutputTarget::explicit(output, options.overwrite != 0) {
                Ok(target) => target,
                Err(_) => return FfiCropResult::failure(CropStatus::Output, 0),
            }
        };
        let Some(final_path) = target.path().to_str().map(str::as_bytes).map(Vec::from) else {
            return FfiCropResult::failure(CropStatus::InvalidPath, 0);
        };
        if result_path.is_null() || final_path.len() > result_path_capacity {
            return FfiCropResult::failure(CropStatus::ResultPathTooLong, 0);
        }
        let output_size = match (options.output_width, options.output_height) {
            (0, 0) => None,
            (0, _) | (_, 0) => return FfiCropResult::failure(CropStatus::InvalidRequest, 0),
            values => Some(values),
        };
        let filter = match options.resize_filter {
            0 => ResizeFilter::Nearest,
            1 => ResizeFilter::Bilinear,
            _ => return FfiCropResult::failure(CropStatus::InvalidRequest, 0),
        };
        let request = FileCropRequest {
            region,
            output_size,
            aspect_mismatch_policy,
            resize_filter: filter,
            limits: PixelLimits::default(),
            output_codec,
        };
        match process_image_file(input, target, request) {
            Ok(result) => {
                // SAFETY: Validated capacity above and guaranteed by caller.
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        final_path.as_ptr(),
                        result_path,
                        final_path.len(),
                    )
                };
                FfiCropResult {
                    status: CropStatus::Ok as i32,
                    reason: 0,
                    path_length: final_path.len(),
                    is_managed: u8::from(result.is_managed),
                    _reserved: [0; 7],
                }
            }
            Err(error) => crop_failure(&error),
        }
    })
    .unwrap_or_else(|_| FfiCropResult::failure(CropStatus::Panic, 0))
}

/// Crops already decoded, orientation-normalized RGBA8 pixels. Platform image
/// decoders use this entry point so the decoded frame never crosses Dart or a
/// temporary image file.
///
/// The pixel memory is borrowed only for this synchronous call.
///
/// # Safety
/// `pixels` must reference `pixels_length` readable bytes. Every path pointer
/// follows the same contract as [`file_image_cropper_crop_image`], `options`
/// must be readable, and `result_path` must have `result_path_capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn file_image_cropper_crop_rgba(
    pixels: *const u8,
    pixels_length: usize,
    width: u32,
    height: u32,
    stride: usize,
    output_bytes: *const u8,
    output_length: usize,
    managed_root_bytes: *const u8,
    managed_root_length: usize,
    options: *const FfiCropOptions,
    result_path: *mut u8,
    result_path_capacity: usize,
) -> FfiCropResult {
    std::panic::catch_unwind(|| {
        if (pixels.is_null() && pixels_length != 0) || options.is_null() {
            return FfiCropResult::failure(CropStatus::InvalidRequest, 0);
        }
        let pixel_bytes = if pixels_length == 0 {
            &[]
        } else {
            // SAFETY: Guaranteed by the function's caller contract.
            unsafe { std::slice::from_raw_parts(pixels, pixels_length) }
        };
        // SAFETY: Guaranteed by the function's caller contract.
        let options = unsafe { *options };
        let request = match file_request_from_options(&options) {
            Ok(request) => request,
            Err(result) => return result,
        };
        let target = match unsafe {
            output_target_from_ffi(
                output_bytes,
                output_length,
                managed_root_bytes,
                managed_root_length,
                &options,
                request.output_codec,
            )
        } {
            Ok(target) => target,
            Err(result) => return result,
        };
        let Some(final_path) = target.path().to_str().map(str::as_bytes).map(Vec::from) else {
            return FfiCropResult::failure(CropStatus::InvalidPath, 0);
        };
        if result_path.is_null() || final_path.len() > result_path_capacity {
            return FfiCropResult::failure(CropStatus::ResultPathTooLong, 0);
        }
        let view = match PixelView::new_rgba8(width, height, stride, pixel_bytes, request.limits) {
            Ok(view) => view,
            Err(error) => {
                return FfiCropResult::failure(CropStatus::InvalidRequest, pixel_reason(&error));
            }
        };
        match process_rgba_view_file(view, target, request) {
            Ok(result) => {
                // SAFETY: Capacity was validated above.
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        final_path.as_ptr(),
                        result_path,
                        final_path.len(),
                    )
                };
                FfiCropResult {
                    status: CropStatus::Ok as i32,
                    reason: 0,
                    path_length: final_path.len(),
                    is_managed: u8::from(result.is_managed),
                    _reserved: [0; 7],
                }
            }
            Err(error) => crop_failure(&error),
        }
    })
    .unwrap_or_else(|_| FfiCropResult::failure(CropStatus::Panic, 0))
}

fn file_request_from_options(options: &FfiCropOptions) -> Result<FileCropRequest, FfiCropResult> {
    let Some(region) = crop_region(options) else {
        return Err(FfiCropResult::failure(CropStatus::InvalidRequest, 0));
    };
    let aspect_mismatch_policy = match options.aspect_policy {
        0 => AspectMismatchPolicy::Reject,
        1 => AspectMismatchPolicy::AdjustCrop,
        2 => AspectMismatchPolicy::Stretch,
        _ => return Err(FfiCropResult::failure(CropStatus::InvalidRequest, 0)),
    };
    let output_codec = match options.output_format {
        0 if (1..=100).contains(&options.jpeg_quality)
            && options.jpeg_background_red <= u8::MAX as u32
            && options.jpeg_background_green <= u8::MAX as u32
            && options.jpeg_background_blue <= u8::MAX as u32 =>
        {
            OutputCodec::Jpeg {
                quality: options.jpeg_quality as u8,
                background: [
                    options.jpeg_background_red as u8,
                    options.jpeg_background_green as u8,
                    options.jpeg_background_blue as u8,
                ],
            }
        }
        1 => OutputCodec::Png,
        2 if options.webp_quality <= 100 && options.webp_lossless <= 1 => OutputCodec::WebP {
            lossless: options.webp_lossless != 0,
            quality: options.webp_quality as u8,
        },
        0 | 2 => return Err(FfiCropResult::failure(CropStatus::InvalidRequest, 0)),
        _ => return Err(FfiCropResult::failure(CropStatus::UnsupportedFormat, 0)),
    };
    let output_size = match (options.output_width, options.output_height) {
        (0, 0) => None,
        (0, _) | (_, 0) => {
            return Err(FfiCropResult::failure(CropStatus::InvalidRequest, 0));
        }
        values => Some(values),
    };
    let resize_filter = match options.resize_filter {
        0 => ResizeFilter::Nearest,
        1 => ResizeFilter::Bilinear,
        _ => return Err(FfiCropResult::failure(CropStatus::InvalidRequest, 0)),
    };
    Ok(FileCropRequest {
        region,
        output_size,
        aspect_mismatch_policy,
        resize_filter,
        limits: PixelLimits::default(),
        output_codec,
    })
}

unsafe fn output_target_from_ffi(
    output_bytes: *const u8,
    output_length: usize,
    managed_root_bytes: *const u8,
    managed_root_length: usize,
    options: &FfiCropOptions,
    output_codec: OutputCodec,
) -> Result<OutputTarget, FfiCropResult> {
    if output_length == 0 {
        // SAFETY: Forwarded from the caller contract.
        let Some(root) = (unsafe { utf8_path(managed_root_bytes, managed_root_length) }) else {
            return Err(FfiCropResult::failure(CropStatus::InvalidPath, 0));
        };
        OutputTarget::managed(root, output_codec.file_type())
            .map_err(|_| FfiCropResult::failure(CropStatus::Output, 0))
    } else {
        // SAFETY: Forwarded from the caller contract.
        let Some(output) = (unsafe { utf8_path(output_bytes, output_length) }) else {
            return Err(FfiCropResult::failure(CropStatus::InvalidPath, 0));
        };
        OutputTarget::explicit(output, options.overwrite != 0)
            .map_err(|_| FfiCropResult::failure(CropStatus::Output, 0))
    }
}

fn crop_region(options: &FfiCropOptions) -> Option<CropRegion> {
    match options.region_type {
        0 => Some(CropRegion::Pixels(CropRect {
            x: exact_u32(options.region_a)?,
            y: exact_u32(options.region_b)?,
            width: exact_u32(options.region_c)?,
            height: exact_u32(options.region_d)?,
        })),
        1 => Some(CropRegion::Normalized {
            left: options.region_a,
            top: options.region_b,
            width: options.region_c,
            height: options.region_d,
        }),
        2 => Some(CropRegion::Centered {
            aspect_ratio: options.region_a,
        }),
        _ => None,
    }
}

fn exact_u32(value: f64) -> Option<u32> {
    (value.is_finite() && value >= 0.0 && value <= u32::MAX as f64 && value.fract() == 0.0)
        .then_some(value as u32)
}

unsafe fn utf8_path<'a>(bytes: *const u8, length: usize) -> Option<&'a Path> {
    if bytes.is_null() {
        return (length == 0).then(|| Path::new(""));
    }
    // SAFETY: Guaranteed by the caller contract.
    let bytes = unsafe { std::slice::from_raw_parts(bytes, length) };
    std::str::from_utf8(bytes).ok().map(Path::new)
}

fn crop_failure(error: &FileProcessError) -> FfiCropResult {
    match error {
        FileProcessError::Input(Error::UnsupportedImageFormat(_)) => {
            FfiCropResult::failure(CropStatus::UnsupportedFormat, 0)
        }
        FileProcessError::Input(Error::InvalidImage { .. }) => {
            FfiCropResult::failure(CropStatus::Decode, 0)
        }
        FileProcessError::Input(_) => FfiCropResult::failure(CropStatus::Input, 0),
        FileProcessError::Output(_) => FfiCropResult::failure(CropStatus::Output, 0),
        FileProcessError::Decode(CodecError::Png(_))
        | FileProcessError::Decode(CodecError::Jpeg(_))
        | FileProcessError::Decode(CodecError::WebP(_)) => {
            FfiCropResult::failure(CropStatus::Decode, 0)
        }
        FileProcessError::Encode(CodecError::Png(_))
        | FileProcessError::Encode(CodecError::Jpeg(_))
        | FileProcessError::Encode(CodecError::WebP(_)) => {
            FfiCropResult::failure(CropStatus::Encode, 0)
        }
        FileProcessError::Pixels(error) => {
            FfiCropResult::failure(CropStatus::InvalidRequest, pixel_reason(error))
        }
    }
}

fn pixel_reason(error: &PixelError) -> u32 {
    match error {
        PixelError::ZeroDimensions => 1,
        PixelError::DimensionOverflow => 2,
        PixelError::BufferSizeMismatch { .. } => 3,
        PixelError::PixelLimitExceeded { .. } => 4,
        PixelError::AllocationLimitExceeded { .. } | PixelError::AllocationFailed { .. } => 5,
        PixelError::InvalidCrop => 6,
        PixelError::InvalidOrientation(_) => 7,
        PixelError::InvalidRowLayout => 8,
        PixelError::AspectMismatch => 9,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn reports_invalid_utf8_without_panicking() {
        let bytes = [0xff];
        // SAFETY: `bytes` remains valid for the duration of the call.
        let result = unsafe { file_image_cropper_inspect_image(bytes.as_ptr(), bytes.len()) };
        assert_eq!(result.status, ImageInfoStatus::InvalidPathEncoding as i32);
    }

    #[test]
    fn crops_borrowed_rgba_without_an_intermediate_file() {
        let token = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "file_image_cropper_ffi_rgba_{}_{token}",
            std::process::id()
        ));
        fs::create_dir(&directory).unwrap();
        let output = directory.join("result.png");
        let output_bytes = output.to_str().unwrap().as_bytes();
        let pixels = [
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
        ];
        let options = FfiCropOptions {
            region_type: 0,
            aspect_policy: 0,
            region_a: 0.0,
            region_b: 0.0,
            region_c: 2.0,
            region_d: 2.0,
            output_width: 2,
            output_height: 2,
            resize_filter: 1,
            output_format: 1,
            jpeg_quality: 90,
            jpeg_background_red: 255,
            jpeg_background_green: 255,
            jpeg_background_blue: 255,
            webp_lossless: 0,
            webp_quality: 80,
            overwrite: 0,
        };
        let mut result_path = vec![0_u8; 1024];
        // SAFETY: Every pointer references a live buffer for this call.
        let result = unsafe {
            file_image_cropper_crop_rgba(
                pixels.as_ptr(),
                pixels.len(),
                2,
                2,
                8,
                output_bytes.as_ptr(),
                output_bytes.len(),
                std::ptr::null(),
                0,
                &options,
                result_path.as_mut_ptr(),
                result_path.len(),
            )
        };
        assert_eq!(result.status, CropStatus::Ok as i32);
        assert_eq!(&result_path[..result.path_length], output_bytes);
        assert_eq!(
            image_info::inspect_path(&output).unwrap().format,
            ImageFormat::Png
        );
        fs::remove_dir_all(directory).unwrap();
    }
}
