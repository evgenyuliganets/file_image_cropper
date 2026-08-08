//! JPEG decode and encode support.

use std::fmt;
use std::io::{BufReader, Read, Seek, Write};

use jpeg_rusturbo::{ChromaSubsampling, JpegEncoder};
use zune_jpeg::zune_core::colorspace::ColorSpace;
use zune_jpeg::zune_core::options::DecoderOptions;
use zune_jpeg::{JpegDecoder, errors::DecodeErrors};

use crate::pixel::{PixelBuffer, PixelError, PixelLimits, RGBA_CHANNELS, allocation_size};
use crate::threading::shared_executor;

pub const DEFAULT_QUALITY: u8 = 90;
pub const DEFAULT_BACKGROUND: [u8; 3] = [255, 255, 255];

#[derive(Debug)]
pub enum JpegCodecError {
    Decode(DecodeErrors),
    Encode(std::io::Error),
    Pixels(PixelError),
    InvalidQuality(u8),
    DimensionsTooLarge { width: u32, height: u32 },
    MissingImageInfo,
    AllocationFailed,
}

impl fmt::Display for JpegCodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Decode(error) => write!(formatter, "JPEG decode failed: {error}"),
            Self::Encode(error) => write!(formatter, "JPEG encode failed: {error}"),
            Self::Pixels(error) => error.fmt(formatter),
            Self::InvalidQuality(quality) => {
                write!(formatter, "JPEG quality {quality} is outside 1..=100")
            }
            Self::DimensionsTooLarge { width, height } => write!(
                formatter,
                "JPEG dimensions {width}x{height} exceed the format limit"
            ),
            Self::MissingImageInfo => formatter.write_str("JPEG dimensions are missing"),
            Self::AllocationFailed => formatter.write_str("unable to allocate JPEG pixel buffer"),
        }
    }
}

impl std::error::Error for JpegCodecError {}

impl From<PixelError> for JpegCodecError {
    fn from(error: PixelError) -> Self {
        Self::Pixels(error)
    }
}

pub fn decode<R: Read + Seek>(
    reader: R,
    limits: PixelLimits,
) -> Result<PixelBuffer, JpegCodecError> {
    let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::RGBA);
    let mut decoder = JpegDecoder::new_with_options(BufReader::new(reader), options);
    decoder.decode_headers().map_err(JpegCodecError::Decode)?;
    let info = decoder.info().ok_or(JpegCodecError::MissingImageInfo)?;
    let width = u32::from(info.width);
    let height = u32::from(info.height);
    allocation_size(width, height, limits)?;
    let rgba = decoder.decode().map_err(JpegCodecError::Decode)?;
    PixelBuffer::new_rgba8_with_limits(width, height, rgba, limits).map_err(Into::into)
}

pub fn encode<W: Write>(
    writer: W,
    pixels: &PixelBuffer,
    quality: u8,
    background: [u8; 3],
) -> Result<(), JpegCodecError> {
    if !(1..=100).contains(&quality) {
        return Err(JpegCodecError::InvalidQuality(quality));
    }
    let width = u16::try_from(pixels.width()).map_err(|_| JpegCodecError::DimensionsTooLarge {
        width: pixels.width(),
        height: pixels.height(),
    })?;
    let height =
        u16::try_from(pixels.height()).map_err(|_| JpegCodecError::DimensionsTooLarge {
            width: pixels.width(),
            height: pixels.height(),
        })?;
    let mut encoder = JpegEncoder::new_with_quality(writer, quality);
    encoder.set_subsampling(if quality < 90 {
        ChromaSubsampling::Yuv420
    } else {
        ChromaSubsampling::Yuv444
    });
    let available_threads = shared_executor()
        .map(|executor| executor.thread_count())
        .unwrap_or(1);
    let pixel_count = pixels.width() as usize * pixels.height() as usize;
    let thread_count = if pixel_count < 4_000_000 {
        available_threads.min(4)
    } else {
        available_threads
    };
    encoder.set_threads(thread_count as u32);
    if pixels
        .data()
        .chunks_exact(RGBA_CHANNELS)
        .all(|pixel| pixel[3] == 255)
    {
        encoder
            .encode_rgba(pixels.data(), u32::from(width), u32::from(height))
            .map_err(JpegCodecError::Encode)
    } else {
        let rgb = composite_rgb(pixels, background)?;
        encoder
            .encode_rgb(&rgb, u32::from(width), u32::from(height))
            .map_err(JpegCodecError::Encode)
    }
}

fn composite_rgb(pixels: &PixelBuffer, background: [u8; 3]) -> Result<Vec<u8>, JpegCodecError> {
    let rgba = pixels.data();
    let rgb_size = rgba
        .len()
        .checked_div(RGBA_CHANNELS)
        .and_then(|pixels| pixels.checked_mul(3))
        .ok_or(JpegCodecError::AllocationFailed)?;
    let mut rgb = Vec::new();
    rgb.try_reserve_exact(rgb_size)
        .map_err(|_| JpegCodecError::AllocationFailed)?;
    rgb.resize(rgb_size, 0);
    let output_row_elements = pixels.width() as usize * 3;
    let process = |band: &mut [u8], first_output_y: usize| {
        let source_start = first_output_y * pixels.width() as usize * RGBA_CHANNELS;
        let source = &rgba[source_start..];
        for (pixel, destination) in source
            .chunks_exact(RGBA_CHANNELS)
            .zip(band.chunks_exact_mut(3))
        {
            let alpha = u16::from(pixel[3]);
            for channel in 0..3 {
                let foreground = u16::from(pixel[channel]);
                let background = u16::from(background[channel]);
                destination[channel] =
                    ((foreground * alpha + background * (255 - alpha) + 127) / 255) as u8;
            }
        }
    };
    if let Some(executor) = shared_executor() {
        executor
            .for_each_row_band_mut(
                &mut rgb,
                output_row_elements,
                pixels.width() as usize * pixels.height() as usize,
                process,
            )
            .map_err(|_| PixelError::InvalidRowLayout)?;
    } else {
        process(&mut rgb, 0);
    }
    Ok(rgb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn composites_alpha_over_requested_background() {
        assert_eq!(
            composite_rgb(
                &PixelBuffer::new_rgba8(2, 1, vec![255, 0, 0, 128, 1, 2, 3, 0]).unwrap(),
                [255, 255, 255]
            )
            .unwrap(),
            [255, 127, 127, 255, 255, 255]
        );
    }

    #[test]
    fn round_trip_preserves_dimensions_and_opaque_alpha() {
        let input = PixelBuffer::new_rgba8(2, 1, vec![255, 0, 0, 255, 0, 255, 0, 255]).unwrap();
        let mut encoded = Vec::new();
        encode(&mut encoded, &input, 100, DEFAULT_BACKGROUND).unwrap();
        let decoded = decode(Cursor::new(encoded), PixelLimits::default()).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (2, 1));
        assert!(decoded.data().chunks_exact(4).all(|pixel| pixel[3] == 255));
    }

    #[test]
    fn rejects_invalid_quality() {
        let input = PixelBuffer::new_rgba8(1, 1, vec![0, 0, 0, 255]).unwrap();
        assert!(matches!(
            encode(Vec::new(), &input, 0, DEFAULT_BACKGROUND),
            Err(JpegCodecError::InvalidQuality(0))
        ));
    }
}
