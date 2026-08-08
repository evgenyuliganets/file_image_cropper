//! Static WebP decode and encode support.

use std::fmt;
use std::io::{Read, Seek, SeekFrom, Write};

use webp::{BitstreamFeatures, Decoder, Encoder, PixelLayout, WebPConfig, WebPEncodingError};

use crate::pixel::{PixelBuffer, PixelError, PixelLimits, RGBA_CHANNELS, allocation_size};

pub const DEFAULT_QUALITY: u8 = 80;

#[derive(Debug)]
pub enum WebPCodecError {
    Io(std::io::Error),
    InvalidBitstream,
    Animated,
    DecodeFailed,
    Encode(WebPEncodingError),
    ConfigInitializationFailed,
    InvalidQuality(u8),
    Pixels(PixelError),
    InputTooLarge { bytes: u64, limit: usize },
    AllocationFailed,
}

impl fmt::Display for WebPCodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "WebP I/O failed: {error}"),
            Self::InvalidBitstream => formatter.write_str("invalid WebP bitstream"),
            Self::Animated => formatter.write_str("animated WebP is not supported"),
            Self::DecodeFailed => formatter.write_str("WebP decode failed"),
            Self::Encode(error) => write!(formatter, "WebP encode failed: {error:?}"),
            Self::ConfigInitializationFailed => {
                formatter.write_str("unable to initialize WebP encoder configuration")
            }
            Self::InvalidQuality(quality) => {
                write!(formatter, "WebP quality {quality} is outside 0..=100")
            }
            Self::Pixels(error) => error.fmt(formatter),
            Self::InputTooLarge { bytes, limit } => {
                write!(formatter, "WebP input size {bytes} exceeds limit {limit}")
            }
            Self::AllocationFailed => formatter.write_str("unable to allocate WebP buffer"),
        }
    }
}

impl std::error::Error for WebPCodecError {}

impl From<PixelError> for WebPCodecError {
    fn from(error: PixelError) -> Self {
        Self::Pixels(error)
    }
}

pub fn decode<R: Read + Seek>(
    mut reader: R,
    limits: PixelLimits,
) -> Result<PixelBuffer, WebPCodecError> {
    let original_position = reader.stream_position().map_err(WebPCodecError::Io)?;
    let input_end = reader.seek(SeekFrom::End(0)).map_err(WebPCodecError::Io)?;
    reader
        .seek(SeekFrom::Start(original_position))
        .map_err(WebPCodecError::Io)?;
    let input_bytes = input_end.saturating_sub(original_position);
    if input_bytes > limits.max_allocation_bytes as u64 {
        return Err(WebPCodecError::InputTooLarge {
            bytes: input_bytes,
            limit: limits.max_allocation_bytes,
        });
    }
    let input_size = usize::try_from(input_bytes).map_err(|_| WebPCodecError::InputTooLarge {
        bytes: input_bytes,
        limit: limits.max_allocation_bytes,
    })?;
    let mut compressed = Vec::new();
    compressed
        .try_reserve_exact(input_size)
        .map_err(|_| WebPCodecError::AllocationFailed)?;
    let read_limit = u64::try_from(limits.max_allocation_bytes)
        .unwrap_or(u64::MAX)
        .saturating_add(1);
    (&mut reader)
        .take(read_limit)
        .read_to_end(&mut compressed)
        .map_err(WebPCodecError::Io)?;
    if compressed.len() > limits.max_allocation_bytes {
        return Err(WebPCodecError::InputTooLarge {
            bytes: compressed.len() as u64,
            limit: limits.max_allocation_bytes,
        });
    }

    let features = BitstreamFeatures::new(&compressed).ok_or(WebPCodecError::InvalidBitstream)?;
    if features.has_animation() {
        return Err(WebPCodecError::Animated);
    }
    allocation_size(features.width(), features.height(), limits)?;
    let image = Decoder::new(&compressed)
        .decode()
        .ok_or(WebPCodecError::DecodeFailed)?;
    let mut rgba = PixelBuffer::allocate(image.width(), image.height(), limits)?;
    match image.layout() {
        PixelLayout::Rgba => rgba.data_mut().copy_from_slice(&image),
        PixelLayout::Rgb => {
            for (source, destination) in image
                .chunks_exact(3)
                .zip(rgba.data_mut().chunks_exact_mut(RGBA_CHANNELS))
            {
                destination[..3].copy_from_slice(source);
                destination[3] = 255;
            }
        }
    }
    Ok(rgba)
}

pub fn encode<W: Write>(
    mut writer: W,
    pixels: &PixelBuffer,
    lossless: bool,
    quality: u8,
) -> Result<(), WebPCodecError> {
    if quality > 100 {
        return Err(WebPCodecError::InvalidQuality(quality));
    }
    let encoder = Encoder::from_rgba(pixels.data(), pixels.width(), pixels.height());
    let mut config = WebPConfig::new().map_err(|_| WebPCodecError::ConfigInitializationFailed)?;
    config.lossless = i32::from(lossless);
    config.quality = f32::from(quality);
    config.exact = i32::from(lossless);
    config.thread_level = 1;
    let encoded = encoder
        .encode_advanced(&config)
        .map_err(WebPCodecError::Encode)?;
    writer.write_all(&encoded).map_err(WebPCodecError::Io)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn lossless_round_trip_preserves_rgba() {
        let input = PixelBuffer::new_rgba8(2, 1, vec![255, 0, 0, 128, 10, 20, 30, 0]).unwrap();
        let mut encoded = Vec::new();
        encode(&mut encoded, &input, true, DEFAULT_QUALITY).unwrap();
        let decoded = decode(Cursor::new(encoded), PixelLimits::default()).unwrap();
        assert_eq!(decoded, input);
    }

    #[test]
    fn lossy_round_trip_preserves_dimensions_and_alpha_channel() {
        let input = PixelBuffer::new_rgba8(2, 1, vec![255, 0, 0, 128, 0, 255, 0, 255]).unwrap();
        let mut encoded = Vec::new();
        encode(&mut encoded, &input, false, 85).unwrap();
        let decoded = decode(Cursor::new(encoded), PixelLimits::default()).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (2, 1));
        assert_eq!(decoded.data()[3], 128);
        assert_eq!(decoded.data()[7], 255);
    }

    #[test]
    fn rejects_invalid_quality() {
        let input = PixelBuffer::new_rgba8(1, 1, vec![0, 0, 0, 255]).unwrap();
        assert!(matches!(
            encode(Vec::new(), &input, false, 101),
            Err(WebPCodecError::InvalidQuality(101))
        ));
    }
}
