//! PNG decode and encode support.

use std::fmt;
use std::io::{BufReader, Read, Seek, Write};

use crate::pixel::{PixelBuffer, PixelError, PixelLimits, RGBA_CHANNELS, allocation_size};

#[derive(Debug)]
pub enum PngCodecError {
    Decode(png::DecodingError),
    Encode(png::EncodingError),
    Pixels(PixelError),
    Animated,
    UnsupportedColor,
    AllocationFailed,
}

impl fmt::Display for PngCodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Decode(error) => write!(formatter, "PNG decode failed: {error}"),
            Self::Encode(error) => write!(formatter, "PNG encode failed: {error}"),
            Self::Pixels(error) => error.fmt(formatter),
            Self::Animated => formatter.write_str("animated PNG is not supported"),
            Self::UnsupportedColor => formatter.write_str("unsupported normalized PNG color type"),
            Self::AllocationFailed => formatter.write_str("unable to allocate PNG decode buffer"),
        }
    }
}

impl std::error::Error for PngCodecError {}

impl From<PixelError> for PngCodecError {
    fn from(error: PixelError) -> Self {
        Self::Pixels(error)
    }
}

pub fn decode<R: Read + Seek>(
    reader: R,
    limits: PixelLimits,
) -> Result<PixelBuffer, PngCodecError> {
    let mut decoder = png::Decoder::new(BufReader::new(reader));
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().map_err(PngCodecError::Decode)?;
    if reader.info().animation_control.is_some() {
        return Err(PngCodecError::Animated);
    }
    let width = reader.info().width;
    let height = reader.info().height;
    allocation_size(width, height, limits)?;
    let raw_size = reader
        .output_buffer_size()
        .ok_or(PngCodecError::AllocationFailed)?;
    if raw_size > limits.max_allocation_bytes {
        return Err(PixelError::AllocationLimitExceeded {
            bytes: raw_size,
            limit: limits.max_allocation_bytes,
        }
        .into());
    }
    let mut raw = Vec::new();
    raw.try_reserve_exact(raw_size)
        .map_err(|_| PngCodecError::AllocationFailed)?;
    raw.resize(raw_size, 0);
    let output = reader.next_frame(&mut raw).map_err(PngCodecError::Decode)?;
    let raw = &raw[..output.buffer_size()];
    let mut rgba = PixelBuffer::allocate(width, height, limits)?;
    convert_to_rgba(raw, output.color_type, rgba.data_mut())?;
    Ok(rgba)
}

fn convert_to_rgba(
    source: &[u8],
    color_type: png::ColorType,
    destination: &mut [u8],
) -> Result<(), PngCodecError> {
    match color_type {
        png::ColorType::Rgba => destination.copy_from_slice(source),
        png::ColorType::Rgb => {
            for (source, destination) in source
                .chunks_exact(3)
                .zip(destination.chunks_exact_mut(RGBA_CHANNELS))
            {
                destination[..3].copy_from_slice(source);
                destination[3] = 255;
            }
        }
        png::ColorType::GrayscaleAlpha => {
            for (source, destination) in source
                .chunks_exact(2)
                .zip(destination.chunks_exact_mut(RGBA_CHANNELS))
            {
                destination[..3].fill(source[0]);
                destination[3] = source[1];
            }
        }
        png::ColorType::Grayscale => {
            for (&source, destination) in source
                .iter()
                .zip(destination.chunks_exact_mut(RGBA_CHANNELS))
            {
                destination[..3].fill(source);
                destination[3] = 255;
            }
        }
        png::ColorType::Indexed => return Err(PngCodecError::UnsupportedColor),
    }
    Ok(())
}

pub fn encode<W: Write>(writer: W, pixels: &PixelBuffer) -> Result<(), PngCodecError> {
    let mut encoder = png::Encoder::new(writer, pixels.width(), pixels.height());
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().map_err(PngCodecError::Encode)?;
    writer
        .write_image_data(pixels.data())
        .map_err(PngCodecError::Encode)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn round_trips_rgba_pixels() {
        let input = PixelBuffer::new_rgba8(2, 1, vec![255, 0, 0, 255, 0, 128, 255, 64]).unwrap();
        let mut encoded = Vec::new();
        encode(&mut encoded, &input).unwrap();
        let decoded = decode(Cursor::new(encoded), PixelLimits::default()).unwrap();
        assert_eq!(decoded, input);
    }

    #[test]
    fn expands_grayscale_to_rgba() {
        let mut encoded = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut encoded, 1, 1);
            encoder.set_color(png::ColorType::Grayscale);
            encoder.set_depth(png::BitDepth::Eight);
            encoder
                .write_header()
                .unwrap()
                .write_image_data(&[42])
                .unwrap();
        }
        let decoded = decode(Cursor::new(encoded), PixelLimits::default()).unwrap();
        assert_eq!(decoded.data(), &[42, 42, 42, 255]);
    }
}
