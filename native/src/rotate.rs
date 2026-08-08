//! EXIF orientation normalization into top-left RGBA8 pixels.

use crate::crop::CropRect;
use crate::pixel::{PixelBuffer, PixelError, PixelLimits, PixelView, RGBA_CHANNELS};
use crate::threading::ParallelExecutor;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum Orientation {
    Normal = 1,
    MirrorHorizontal = 2,
    Rotate180 = 3,
    MirrorVertical = 4,
    Transpose = 5,
    Rotate90Clockwise = 6,
    Transverse = 7,
    Rotate90CounterClockwise = 8,
}

pub fn oriented_dimensions(width: u32, height: u32, orientation: Orientation) -> (u32, u32) {
    if swaps_dimensions(orientation) {
        (height, width)
    } else {
        (width, height)
    }
}

pub fn source_crop_for_oriented_rect(
    source_width: u32,
    source_height: u32,
    orientation: Orientation,
    rect: CropRect,
) -> Result<CropRect, PixelError> {
    let (oriented_width, oriented_height) =
        oriented_dimensions(source_width, source_height, orientation);
    rect.validate(oriented_width, oriented_height)?;
    let last_x = rect.x + rect.width - 1;
    let last_y = rect.y + rect.height - 1;
    let points = [
        (rect.x, rect.y),
        (last_x, rect.y),
        (rect.x, last_y),
        (last_x, last_y),
    ];
    let corners = points.map(|(x, y)| {
        source_coordinate(
            orientation,
            source_width as usize,
            source_height as usize,
            x as usize,
            y as usize,
        )
    });
    let min_x = corners.iter().map(|corner| corner.0).min().unwrap();
    let max_x = corners.iter().map(|corner| corner.0).max().unwrap();
    let min_y = corners.iter().map(|corner| corner.1).min().unwrap();
    let max_y = corners.iter().map(|corner| corner.1).max().unwrap();
    Ok(CropRect {
        x: min_x as u32,
        y: min_y as u32,
        width: (max_x - min_x + 1) as u32,
        height: (max_y - min_y + 1) as u32,
    })
}

impl TryFrom<u8> for Orientation {
    type Error = PixelError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Normal),
            2 => Ok(Self::MirrorHorizontal),
            3 => Ok(Self::Rotate180),
            4 => Ok(Self::MirrorVertical),
            5 => Ok(Self::Transpose),
            6 => Ok(Self::Rotate90Clockwise),
            7 => Ok(Self::Transverse),
            8 => Ok(Self::Rotate90CounterClockwise),
            _ => Err(PixelError::InvalidOrientation(value)),
        }
    }
}

pub fn normalize_orientation(
    input: PixelView<'_>,
    orientation: Orientation,
    limits: PixelLimits,
    executor: Option<&ParallelExecutor>,
) -> Result<PixelBuffer, PixelError> {
    let (output_width, output_height) =
        oriented_dimensions(input.width(), input.height(), orientation);
    let mut output = PixelBuffer::allocate(output_width, output_height, limits)?;
    let output_row_elements = output_width as usize * RGBA_CHANNELS;
    let pixel_count = output_width as usize * output_height as usize;

    let process = |band: &mut [u8], first_output_y: usize| {
        for (local_y, output_row) in band.chunks_mut(output_row_elements).enumerate() {
            let output_y = first_output_y + local_y;
            for output_x in 0..output_width as usize {
                let (source_x, source_y) = source_coordinate(
                    orientation,
                    input.width() as usize,
                    input.height() as usize,
                    output_x,
                    output_y,
                );
                let source = &input.row(source_y as u32)
                    [source_x * RGBA_CHANNELS..(source_x + 1) * RGBA_CHANNELS];
                output_row[output_x * RGBA_CHANNELS..(output_x + 1) * RGBA_CHANNELS]
                    .copy_from_slice(source);
            }
        }
    };

    if let Some(executor) = executor {
        executor
            .for_each_row_band_mut(output.data_mut(), output_row_elements, pixel_count, process)
            .map_err(|_| PixelError::InvalidRowLayout)?;
    } else {
        process(output.data_mut(), 0);
    }
    Ok(output)
}

fn swaps_dimensions(orientation: Orientation) -> bool {
    matches!(
        orientation,
        Orientation::Transpose
            | Orientation::Rotate90Clockwise
            | Orientation::Transverse
            | Orientation::Rotate90CounterClockwise
    )
}

fn source_coordinate(
    orientation: Orientation,
    width: usize,
    height: usize,
    x: usize,
    y: usize,
) -> (usize, usize) {
    match orientation {
        Orientation::Normal => (x, y),
        Orientation::MirrorHorizontal => (width - 1 - x, y),
        Orientation::Rotate180 => (width - 1 - x, height - 1 - y),
        Orientation::MirrorVertical => (x, height - 1 - y),
        Orientation::Transpose => (y, x),
        Orientation::Rotate90Clockwise => (y, height - 1 - x),
        Orientation::Transverse => (width - 1 - y, height - 1 - x),
        Orientation::Rotate90CounterClockwise => (width - 1 - y, x),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn labeled_pixels() -> PixelBuffer {
        let mut data = Vec::new();
        for value in 1..=6 {
            data.extend_from_slice(&[value, 0, 0, 255]);
        }
        PixelBuffer::new_rgba8(3, 2, data).unwrap()
    }

    fn labels(buffer: &PixelBuffer) -> Vec<u8> {
        buffer
            .data()
            .chunks_exact(4)
            .map(|pixel| pixel[0])
            .collect()
    }

    #[test]
    fn normalizes_all_exif_orientations() {
        let input = labeled_pixels();
        let expected = [
            (Orientation::Normal, 3, 2, vec![1, 2, 3, 4, 5, 6]),
            (Orientation::MirrorHorizontal, 3, 2, vec![3, 2, 1, 6, 5, 4]),
            (Orientation::Rotate180, 3, 2, vec![6, 5, 4, 3, 2, 1]),
            (Orientation::MirrorVertical, 3, 2, vec![4, 5, 6, 1, 2, 3]),
            (Orientation::Transpose, 2, 3, vec![1, 4, 2, 5, 3, 6]),
            (Orientation::Rotate90Clockwise, 2, 3, vec![4, 1, 5, 2, 6, 3]),
            (Orientation::Transverse, 2, 3, vec![6, 3, 5, 2, 4, 1]),
            (
                Orientation::Rotate90CounterClockwise,
                2,
                3,
                vec![3, 6, 2, 5, 1, 4],
            ),
        ];
        for (orientation, width, height, expected_labels) in expected {
            let output =
                normalize_orientation(input.view(), orientation, PixelLimits::default(), None)
                    .unwrap();
            assert_eq!((output.width(), output.height()), (width, height));
            assert_eq!(labels(&output), expected_labels, "{orientation:?}");
        }
    }

    #[test]
    fn maps_oriented_crop_back_to_minimal_source_rectangle() {
        assert_eq!(
            source_crop_for_oriented_rect(
                3,
                2,
                Orientation::Rotate90Clockwise,
                CropRect {
                    x: 0,
                    y: 1,
                    width: 2,
                    height: 2,
                }
            )
            .unwrap(),
            CropRect {
                x: 1,
                y: 0,
                width: 2,
                height: 2,
            }
        );
    }
}
