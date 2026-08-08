//! Header and metadata inspection without a full image decode.

use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use crate::error::{Error, InvalidImageReason, Result};
use crate::filesystem::open_input;

const MAX_HEADER_BYTES: u64 = 32 * 1024 * 1024;

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImageFormat {
    Jpeg = 1,
    Png = 2,
    WebP = 3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub format: ImageFormat,
    /// EXIF orientation in the inclusive range 1..=8.
    pub orientation: u8,
}

pub fn inspect_path(path: &Path) -> Result<ImageInfo> {
    let mut file = open_input(path)?;
    inspect_reader(&mut file).map_err(|failure| match failure {
        InspectFailure::Unsupported => Error::UnsupportedImageFormat(path.to_path_buf()),
        InspectFailure::Invalid(reason) => Error::InvalidImage {
            path: path.to_path_buf(),
            reason,
        },
        InspectFailure::Io(error) => Error::io("read image metadata", path, error),
    })
}

/// Reader-based core kept independent of filesystem input for future file
/// descriptor and in-memory adapters.
pub fn inspect_reader<R: Read + Seek>(
    reader: &mut R,
) -> std::result::Result<ImageInfo, InspectFailure> {
    reader
        .seek(SeekFrom::Start(0))
        .map_err(InspectFailure::Io)?;
    let mut bytes = Vec::new();
    reader
        .take(MAX_HEADER_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(InspectFailure::Io)?;
    if bytes.len() as u64 > MAX_HEADER_BYTES {
        return Err(InspectFailure::Invalid(
            InvalidImageReason::InspectionLimitExceeded,
        ));
    }
    inspect_bytes(&bytes)
}

#[derive(Debug)]
pub enum InspectFailure {
    Unsupported,
    Invalid(InvalidImageReason),
    Io(std::io::Error),
}

fn inspect_bytes(bytes: &[u8]) -> std::result::Result<ImageInfo, InspectFailure> {
    if bytes.starts_with(&[0xff, 0xd8]) {
        inspect_jpeg(bytes)
    } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        inspect_png(bytes)
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        inspect_webp(bytes)
    } else {
        Err(InspectFailure::Unsupported)
    }
}

fn inspect_jpeg(bytes: &[u8]) -> std::result::Result<ImageInfo, InspectFailure> {
    let mut offset = 2;
    let mut dimensions = None;
    let mut orientation = 1;
    while offset < bytes.len() {
        while offset < bytes.len() && bytes[offset] == 0xff {
            offset += 1;
        }
        let marker = *bytes
            .get(offset)
            .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))?;
        offset += 1;
        if marker == 0xd9 || marker == 0xda {
            break;
        }
        if marker == 0x01 || (0xd0..=0xd7).contains(&marker) {
            continue;
        }
        let length = read_be_u16(bytes, offset)? as usize;
        if length < 2 || offset + length > bytes.len() {
            return Err(InspectFailure::Invalid(
                InvalidImageReason::InvalidStructure,
            ));
        }
        let segment = &bytes[offset + 2..offset + length];
        if is_sof(marker) {
            if segment.len() < 5 {
                return Err(InspectFailure::Invalid(InvalidImageReason::Truncated));
            }
            dimensions = Some((
                read_be_u16(segment, 3)? as u32,
                read_be_u16(segment, 1)? as u32,
            ));
        } else if marker == 0xe1 && segment.starts_with(b"Exif\0\0") {
            orientation = parse_exif_orientation(&segment[6..]).unwrap_or(1);
        }
        offset += length;
    }
    let (width, height) = dimensions.ok_or(InspectFailure::Invalid(
        InvalidImageReason::DimensionsMissing,
    ))?;
    validate_dimensions(width, height)?;
    Ok(ImageInfo {
        width,
        height,
        format: ImageFormat::Jpeg,
        orientation,
    })
}

fn is_sof(marker: u8) -> bool {
    matches!(marker, 0xc0..=0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf)
}

fn inspect_png(bytes: &[u8]) -> std::result::Result<ImageInfo, InspectFailure> {
    if bytes.len() < 33 || &bytes[12..16] != b"IHDR" {
        return Err(InspectFailure::Invalid(
            InvalidImageReason::InvalidStructure,
        ));
    }
    let width = read_be_u32(bytes, 16)?;
    let height = read_be_u32(bytes, 20)?;
    validate_dimensions(width, height)?;
    let mut orientation = 1;
    let mut offset = 8;
    while offset + 12 <= bytes.len() {
        let length = read_be_u32(bytes, offset)? as usize;
        let end = offset
            .checked_add(12)
            .and_then(|value| value.checked_add(length))
            .ok_or(InspectFailure::Invalid(
                InvalidImageReason::InvalidStructure,
            ))?;
        if end > bytes.len() {
            return Err(InspectFailure::Invalid(InvalidImageReason::Truncated));
        }
        if &bytes[offset + 4..offset + 8] == b"eXIf" {
            orientation =
                parse_exif_orientation(&bytes[offset + 8..offset + 8 + length]).unwrap_or(1);
        }
        if &bytes[offset + 4..offset + 8] == b"IEND" {
            break;
        }
        offset = end;
    }
    Ok(ImageInfo {
        width,
        height,
        format: ImageFormat::Png,
        orientation,
    })
}

fn inspect_webp(bytes: &[u8]) -> std::result::Result<ImageInfo, InspectFailure> {
    let mut offset = 12;
    let mut dimensions = None;
    let mut orientation = 1;
    while offset + 8 <= bytes.len() {
        let kind = &bytes[offset..offset + 4];
        let length = read_le_u32(bytes, offset + 4)? as usize;
        let data_start = offset + 8;
        let data_end = data_start
            .checked_add(length)
            .ok_or(InspectFailure::Invalid(
                InvalidImageReason::InvalidStructure,
            ))?;
        if data_end > bytes.len() {
            return Err(InspectFailure::Invalid(InvalidImageReason::Truncated));
        }
        let data = &bytes[data_start..data_end];
        match kind {
            b"VP8X" if data.len() >= 10 => {
                if data[0] & 0x02 != 0 {
                    return Err(InspectFailure::Invalid(
                        InvalidImageReason::AnimatedUnsupported,
                    ));
                }
                dimensions = Some((read_le_u24(data, 4)? + 1, read_le_u24(data, 7)? + 1))
            }
            b"VP8L" if data.len() >= 5 && data[0] == 0x2f => {
                let packed = read_le_u32(data, 1)?;
                dimensions = Some(((packed & 0x3fff) + 1, ((packed >> 14) & 0x3fff) + 1));
            }
            b"VP8 " if data.len() >= 10 && &data[3..6] == b"\x9d\x01\x2a" => {
                dimensions = Some((
                    (read_le_u16(data, 6)? & 0x3fff) as u32,
                    (read_le_u16(data, 8)? & 0x3fff) as u32,
                ))
            }
            b"EXIF" => {
                orientation = parse_exif_orientation(data.strip_prefix(b"Exif\0\0").unwrap_or(data))
                    .unwrap_or(1)
            }
            _ => {}
        }
        offset = data_end + (length & 1);
    }
    let (width, height) = dimensions.ok_or(InspectFailure::Invalid(
        InvalidImageReason::DimensionsMissing,
    ))?;
    validate_dimensions(width, height)?;
    Ok(ImageInfo {
        width,
        height,
        format: ImageFormat::WebP,
        orientation,
    })
}

fn parse_exif_orientation(tiff: &[u8]) -> Option<u8> {
    if tiff.len() < 8 {
        return None;
    }
    let little = match &tiff[..2] {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let u16_at = |offset| read_u16_order(tiff, offset, little);
    let u32_at = |offset| read_u32_order(tiff, offset, little);
    if u16_at(2)? != 42 {
        return None;
    }
    let ifd = u32_at(4)? as usize;
    let count = u16_at(ifd)? as usize;
    for index in 0..count {
        let entry = ifd.checked_add(2 + index * 12)?;
        if entry + 12 > tiff.len() {
            return None;
        }
        if u16_at(entry)? == 0x0112 && u16_at(entry + 2)? == 3 && u32_at(entry + 4)? >= 1 {
            let value = u16_at(entry + 8)? as u8;
            return (1..=8).contains(&value).then_some(value);
        }
    }
    None
}

fn validate_dimensions(width: u32, height: u32) -> std::result::Result<(), InspectFailure> {
    if width == 0 || height == 0 {
        Err(InspectFailure::Invalid(InvalidImageReason::ZeroDimensions))
    } else {
        Ok(())
    }
}

fn read_be_u16(bytes: &[u8], offset: usize) -> std::result::Result<u16, InspectFailure> {
    bytes
        .get(offset..offset + 2)
        .map(|v| u16::from_be_bytes([v[0], v[1]]))
        .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))
}
fn read_le_u16(bytes: &[u8], offset: usize) -> std::result::Result<u16, InspectFailure> {
    bytes
        .get(offset..offset + 2)
        .map(|v| u16::from_le_bytes([v[0], v[1]]))
        .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))
}
fn read_be_u32(bytes: &[u8], offset: usize) -> std::result::Result<u32, InspectFailure> {
    bytes
        .get(offset..offset + 4)
        .map(|v| u32::from_be_bytes([v[0], v[1], v[2], v[3]]))
        .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))
}
fn read_le_u32(bytes: &[u8], offset: usize) -> std::result::Result<u32, InspectFailure> {
    bytes
        .get(offset..offset + 4)
        .map(|v| u32::from_le_bytes([v[0], v[1], v[2], v[3]]))
        .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))
}
fn read_le_u24(bytes: &[u8], offset: usize) -> std::result::Result<u32, InspectFailure> {
    bytes
        .get(offset..offset + 3)
        .map(|v| u32::from(v[0]) | (u32::from(v[1]) << 8) | (u32::from(v[2]) << 16))
        .ok_or(InspectFailure::Invalid(InvalidImageReason::Truncated))
}
fn read_u16_order(bytes: &[u8], offset: usize, little: bool) -> Option<u16> {
    let v = bytes.get(offset..offset + 2)?;
    Some(if little {
        u16::from_le_bytes([v[0], v[1]])
    } else {
        u16::from_be_bytes([v[0], v[1]])
    })
}
fn read_u32_order(bytes: &[u8], offset: usize, little: bool) -> Option<u32> {
    let v = bytes.get(offset..offset + 4)?;
    Some(if little {
        u32::from_le_bytes([v[0], v[1], v[2], v[3]])
    } else {
        u32::from_be_bytes([v[0], v[1], v[2], v[3]])
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn inspects_png_by_signature_not_extension() {
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend_from_slice(&640u32.to_be_bytes());
        png.extend_from_slice(&480u32.to_be_bytes());
        png.extend_from_slice(&[8, 6, 0, 0, 0, 0, 0, 0, 0]);
        let info = inspect_reader(&mut Cursor::new(png)).unwrap();
        assert_eq!(
            info,
            ImageInfo {
                width: 640,
                height: 480,
                format: ImageFormat::Png,
                orientation: 1
            }
        );
    }

    #[test]
    fn reads_jpeg_dimensions_and_exif_orientation() {
        let mut jpeg = vec![0xff, 0xd8, 0xff, 0xe1, 0, 34];
        jpeg.extend_from_slice(
            b"Exif\0\0II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0",
        );
        jpeg.extend_from_slice(&[
            0xff, 0xc0, 0, 17, 8, 0x01, 0xe0, 0x02, 0x80, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0,
        ]);
        let info = inspect_reader(&mut Cursor::new(jpeg)).unwrap();
        assert_eq!((info.width, info.height, info.orientation), (640, 480, 6));
    }

    #[test]
    fn inspects_extended_webp() {
        let mut webp = b"RIFF\x12\0\0\0WEBPVP8X\x0a\0\0\0\0\0\0\0".to_vec();
        webp.extend_from_slice(&[0x7f, 0x02, 0, 0xdf, 0x01, 0]);
        let info = inspect_reader(&mut Cursor::new(webp)).unwrap();
        assert_eq!(
            (info.width, info.height, info.format),
            (640, 480, ImageFormat::WebP)
        );
    }

    #[test]
    fn rejects_unknown_and_truncated_images() {
        assert!(matches!(
            inspect_reader(&mut Cursor::new(b"not an image")),
            Err(InspectFailure::Unsupported)
        ));
        assert!(matches!(
            inspect_reader(&mut Cursor::new(b"\x89PNG\r\n\x1a\n")),
            Err(InspectFailure::Invalid(_))
        ));
        assert!(matches!(
            inspect_reader(&mut Cursor::new(b"\0\0\0\x18ftypheic")),
            Err(InspectFailure::Unsupported)
        ));
    }

    #[test]
    fn arbitrary_and_mutated_inputs_never_panic() {
        let seeds: [&[u8]; 3] = [
            b"\xff\xd8\xff\xe1\0\x20Exif\0\0",
            b"\x89PNG\r\n\x1a\n",
            b"RIFF\xff\xff\xff\xffWEBPVP8X",
        ];
        let mut state = 0x9e37_79b9_u32;
        for iteration in 0..10_000 {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            let length = (state as usize) & 0x3ff;
            let mut bytes = Vec::with_capacity(length);
            for index in 0..length {
                state ^= state << 13;
                state ^= state >> 17;
                state ^= state << 5;
                let seed = seeds[iteration % seeds.len()];
                let value = if index < seed.len() && iteration % 3 != 0 {
                    seed[index]
                } else {
                    state as u8
                };
                bytes.push(value);
            }
            let result = std::panic::catch_unwind(|| inspect_bytes(&bytes));
            assert!(result.is_ok(), "parser panicked at iteration {iteration}");
        }
    }
}
