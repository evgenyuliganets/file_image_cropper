//! Deterministic nearest and alpha-correct bilinear RGBA8 resize.

use crate::pixel::{PixelBuffer, PixelError, PixelLimits, PixelView, RGBA_CHANNELS};
use crate::threading::ParallelExecutor;

const WEIGHT_ONE: u64 = 65_536;
const WEIGHT_AREA: u64 = WEIGHT_ONE * WEIGHT_ONE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResizeFilter {
    Nearest,
    Bilinear,
}

#[derive(Clone, Copy)]
struct AxisSample {
    first: usize,
    second: usize,
    second_weight: u32,
}

pub fn resize(
    input: PixelView<'_>,
    output_width: u32,
    output_height: u32,
    filter: ResizeFilter,
    limits: PixelLimits,
    executor: Option<&ParallelExecutor>,
) -> Result<PixelBuffer, PixelError> {
    let mut output = PixelBuffer::allocate(output_width, output_height, limits)?;
    let output_row_elements = output_width as usize * RGBA_CHANNELS;
    let pixel_count = output_width as usize * output_height as usize;
    let horizontal = axis_samples(input.width(), output_width, filter);
    let vertical = axis_samples(input.height(), output_height, filter);

    let process = |band: &mut [u8], first_output_y: usize| {
        for (local_y, output_row) in band.chunks_mut(output_row_elements).enumerate() {
            let output_y = first_output_y + local_y;
            let vertical_sample = vertical[output_y];
            let top = input.row(vertical_sample.first as u32);
            let bottom = input.row(vertical_sample.second as u32);
            for (output_x, horizontal_sample) in horizontal.iter().copied().enumerate() {
                let destination =
                    &mut output_row[output_x * RGBA_CHANNELS..(output_x + 1) * RGBA_CHANNELS];
                match filter {
                    ResizeFilter::Nearest => destination.copy_from_slice(
                        &top[horizontal_sample.first * RGBA_CHANNELS
                            ..(horizontal_sample.first + 1) * RGBA_CHANNELS],
                    ),
                    ResizeFilter::Bilinear => {
                        bilinear_pixel(top, bottom, horizontal_sample, vertical_sample, destination)
                    }
                }
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

fn axis_samples(input_size: u32, output_size: u32, filter: ResizeFilter) -> Vec<AxisSample> {
    let input_size = input_size as usize;
    let output_size = output_size as usize;
    (0..output_size)
        .map(|output_index| match filter {
            ResizeFilter::Nearest => {
                let source = (((2 * output_index as u64 + 1) * input_size as u64)
                    / (2 * output_size as u64)) as usize;
                let source = source.min(input_size - 1);
                AxisSample {
                    first: source,
                    second: source,
                    second_weight: 0,
                }
            }
            ResizeFilter::Bilinear => {
                let position =
                    (output_index as f64 + 0.5) * input_size as f64 / output_size as f64 - 0.5;
                if position <= 0.0 {
                    AxisSample {
                        first: 0,
                        second: 0,
                        second_weight: 0,
                    }
                } else if position >= (input_size - 1) as f64 {
                    AxisSample {
                        first: input_size - 1,
                        second: input_size - 1,
                        second_weight: 0,
                    }
                } else {
                    let first = position.floor() as usize;
                    let fraction = position - first as f64;
                    AxisSample {
                        first,
                        second: first + 1,
                        second_weight: (fraction * WEIGHT_ONE as f64).round() as u32,
                    }
                }
            }
        })
        .collect()
}

fn bilinear_pixel(
    top: &[u8],
    bottom: &[u8],
    horizontal: AxisSample,
    vertical: AxisSample,
    destination: &mut [u8],
) {
    let wx1 = horizontal.second_weight as u64;
    let wx0 = WEIGHT_ONE - wx1;
    let wy1 = vertical.second_weight as u64;
    let wy0 = WEIGHT_ONE - wy1;
    let samples = [
        (
            &top[horizontal.first * 4..horizontal.first * 4 + 4],
            wx0 * wy0,
        ),
        (
            &top[horizontal.second * 4..horizontal.second * 4 + 4],
            wx1 * wy0,
        ),
        (
            &bottom[horizontal.first * 4..horizontal.first * 4 + 4],
            wx0 * wy1,
        ),
        (
            &bottom[horizontal.second * 4..horizontal.second * 4 + 4],
            wx1 * wy1,
        ),
    ];
    let mut weighted_alpha = 0_u64;
    let mut weighted_color_alpha = [0_u64; 3];
    for (pixel, weight) in samples {
        let alpha = pixel[3] as u64;
        weighted_alpha += alpha * weight;
        for channel in 0..3 {
            weighted_color_alpha[channel] += pixel[channel] as u64 * alpha * weight;
        }
    }
    destination[3] = ((weighted_alpha + WEIGHT_AREA / 2) / WEIGHT_AREA) as u8;
    if weighted_alpha == 0 {
        destination[..3].fill(0);
    } else {
        for channel in 0..3 {
            destination[channel] =
                ((weighted_color_alpha[channel] + weighted_alpha / 2) / weighted_alpha) as u8;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::threading::{ParallelExecutor, ThreadingPolicy};

    fn pixel(red: u8, alpha: u8) -> [u8; 4] {
        [red, 0, 0, alpha]
    }

    #[test]
    fn nearest_neighbor_preserves_pixel_blocks() {
        let input = PixelBuffer::new_rgba8(
            2,
            2,
            [pixel(1, 255), pixel(2, 255), pixel(3, 255), pixel(4, 255)].concat(),
        )
        .unwrap();
        let output = resize(
            input.view(),
            4,
            4,
            ResizeFilter::Nearest,
            PixelLimits::default(),
            None,
        )
        .unwrap();
        let labels: Vec<_> = output
            .data()
            .chunks_exact(4)
            .map(|value| value[0])
            .collect();
        assert_eq!(labels, vec![1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 4, 4]);
    }

    #[test]
    fn bilinear_is_alpha_correct() {
        let input = PixelBuffer::new_rgba8(2, 1, [pixel(255, 255), pixel(0, 0)].concat()).unwrap();
        let output = resize(
            input.view(),
            1,
            1,
            ResizeFilter::Bilinear,
            PixelLimits::default(),
            None,
        )
        .unwrap();
        assert_eq!(output.data(), &[255, 0, 0, 128]);
    }

    #[test]
    fn sequential_and_parallel_results_are_identical() {
        let data: Vec<u8> = (0..64 * 64)
            .flat_map(|index| {
                let value = index as u8;
                [value, value.wrapping_mul(3), value.wrapping_mul(7), 255]
            })
            .collect();
        let input = PixelBuffer::new_rgba8(64, 64, data).unwrap();
        let sequential = resize(
            input.view(),
            127,
            129,
            ResizeFilter::Bilinear,
            PixelLimits::default(),
            None,
        )
        .unwrap();
        let executor = ParallelExecutor::new(ThreadingPolicy {
            max_threads: 2,
            min_parallel_pixels: 1,
        })
        .unwrap();
        let parallel = resize(
            input.view(),
            127,
            129,
            ResizeFilter::Bilinear,
            PixelLimits::default(),
            Some(&executor),
        )
        .unwrap();
        assert_eq!(sequential, parallel);
    }
}
