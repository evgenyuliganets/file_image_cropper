//! Validated crop geometry and zero-copy borrowed crop views.

use crate::pixel::{PixelBuffer, PixelError, PixelLimits, PixelView, RGBA_CHANNELS};
use crate::threading::ParallelExecutor;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CropRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CropRegion {
    Pixels(CropRect),
    Normalized {
        left: f64,
        top: f64,
        width: f64,
        height: f64,
    },
    Centered {
        aspect_ratio: f64,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AspectMismatchPolicy {
    Reject,
    AdjustCrop,
    Stretch,
}

impl CropRect {
    pub fn full(width: u32, height: u32) -> Self {
        Self {
            x: 0,
            y: 0,
            width,
            height,
        }
    }

    pub fn validate(self, image_width: u32, image_height: u32) -> Result<(), PixelError> {
        if self.width == 0 || self.height == 0 {
            return Err(PixelError::InvalidCrop);
        }
        let right = self
            .x
            .checked_add(self.width)
            .ok_or(PixelError::InvalidCrop)?;
        let bottom = self
            .y
            .checked_add(self.height)
            .ok_or(PixelError::InvalidCrop)?;
        if right > image_width || bottom > image_height {
            return Err(PixelError::InvalidCrop);
        }
        Ok(())
    }
}

pub fn resolve_crop_region(
    region: CropRegion,
    image_width: u32,
    image_height: u32,
    output_size: Option<(u32, u32)>,
    aspect_policy: AspectMismatchPolicy,
) -> Result<CropRect, PixelError> {
    if image_width == 0 || image_height == 0 {
        return Err(PixelError::ZeroDimensions);
    }

    let rect = match region {
        CropRegion::Pixels(rect) => rect,
        CropRegion::Normalized {
            left,
            top,
            width,
            height,
        } => normalized_rect(left, top, width, height, image_width, image_height)?,
        CropRegion::Centered { aspect_ratio } => {
            centered_rect(CropRect::full(image_width, image_height), aspect_ratio)?
        }
    };
    rect.validate(image_width, image_height)?;

    let Some((output_width, output_height)) = output_size else {
        return Ok(rect);
    };
    if output_width == 0 || output_height == 0 {
        return Err(PixelError::ZeroDimensions);
    }

    match aspect_policy {
        AspectMismatchPolicy::Stretch => Ok(rect),
        AspectMismatchPolicy::AdjustCrop => adjust_rect(rect, output_width, output_height),
        AspectMismatchPolicy::Reject => {
            let source_ratio = rect.width as f64 / rect.height as f64;
            let target_ratio = output_width as f64 / output_height as f64;
            let relative_difference = (source_ratio / target_ratio - 1.0).abs();
            let pixel_tolerance = 1.0 / rect.width.min(rect.height) as f64;
            if relative_difference > 0.002_f64.max(pixel_tolerance) {
                Err(PixelError::AspectMismatch)
            } else {
                adjust_rect(rect, output_width, output_height)
            }
        }
    }
}

fn normalized_rect(
    left: f64,
    top: f64,
    width: f64,
    height: f64,
    image_width: u32,
    image_height: u32,
) -> Result<CropRect, PixelError> {
    let values = [left, top, width, height];
    if values.iter().any(|value| !value.is_finite())
        || left < 0.0
        || top < 0.0
        || width <= 0.0
        || height <= 0.0
        || left + width > 1.0 + f64::EPSILON * 8.0
        || top + height > 1.0 + f64::EPSILON * 8.0
    {
        return Err(PixelError::InvalidCrop);
    }

    let x = normalized_coordinate(left, image_width, false);
    let y = normalized_coordinate(top, image_height, false);
    let right = normalized_coordinate((left + width).min(1.0), image_width, true);
    let bottom = normalized_coordinate((top + height).min(1.0), image_height, true);
    Ok(CropRect {
        x,
        y,
        width: right.saturating_sub(x),
        height: bottom.saturating_sub(y),
    })
}

fn normalized_coordinate(value: f64, extent: u32, upper_bound: bool) -> u32 {
    let scaled = value * extent as f64;
    let nearest = scaled.round();
    let tolerance = f64::EPSILON * scaled.abs().max(1.0) * 8.0;
    let stable = if (scaled - nearest).abs() <= tolerance {
        nearest
    } else {
        scaled
    };
    if upper_bound {
        stable.ceil() as u32
    } else {
        stable.floor() as u32
    }
}

fn centered_rect(bounds: CropRect, aspect_ratio: f64) -> Result<CropRect, PixelError> {
    if !aspect_ratio.is_finite() || aspect_ratio <= 0.0 {
        return Err(PixelError::InvalidCrop);
    }
    let bounds_ratio = bounds.width as f64 / bounds.height as f64;
    let (width, height) = if bounds_ratio > aspect_ratio {
        (
            (bounds.height as f64 * aspect_ratio).round() as u32,
            bounds.height,
        )
    } else {
        (
            bounds.width,
            (bounds.width as f64 / aspect_ratio).round() as u32,
        )
    };
    if width == 0 || height == 0 {
        return Err(PixelError::InvalidCrop);
    }
    Ok(CropRect {
        x: bounds.x + (bounds.width - width) / 2,
        y: bounds.y + (bounds.height - height) / 2,
        width,
        height,
    })
}

fn adjust_rect(
    rect: CropRect,
    output_width: u32,
    output_height: u32,
) -> Result<CropRect, PixelError> {
    let target_ratio = output_width as f64 / output_height as f64;
    let source_ratio = rect.width as f64 / rect.height as f64;
    let (width, height) = if source_ratio > target_ratio {
        (
            (rect.height as f64 * target_ratio).round() as u32,
            rect.height,
        )
    } else {
        (
            rect.width,
            (rect.width as f64 / target_ratio).round() as u32,
        )
    };
    if width == 0 || height == 0 || width > rect.width || height > rect.height {
        return Err(PixelError::InvalidCrop);
    }
    Ok(CropRect {
        x: rect.x + (rect.width - width) / 2,
        y: rect.y + (rect.height - height) / 2,
        width,
        height,
    })
}

pub fn crop_view<'a>(image: PixelView<'a>, rect: CropRect) -> Result<PixelView<'a>, PixelError> {
    rect.validate(image.width(), image.height())?;
    Ok(image.crop(rect.x, rect.y, rect.width, rect.height))
}

pub fn materialize_crop(
    image: PixelView<'_>,
    limits: PixelLimits,
    executor: Option<&ParallelExecutor>,
) -> Result<PixelBuffer, PixelError> {
    let mut output = PixelBuffer::allocate(image.width(), image.height(), limits)?;
    let output_stride = image.width() as usize * RGBA_CHANNELS;
    let process = |band: &mut [u8], first_output_y: usize| {
        for (local_y, output_row) in band.chunks_exact_mut(output_stride).enumerate() {
            output_row.copy_from_slice(image.row((first_output_y + local_y) as u32));
        }
    };
    if let Some(executor) = executor {
        executor
            .for_each_row_band_mut(
                output.data_mut(),
                output_stride,
                image.width() as usize * image.height() as usize,
                process,
            )
            .map_err(|_| PixelError::InvalidRowLayout)?;
    } else {
        process(output.data_mut(), 0);
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crop_view_keeps_source_stride_without_copying() {
        let input = PixelBuffer::new_rgba8(3, 2, (0_u8..24).collect()).unwrap();
        let view = crop_view(
            input.view(),
            CropRect {
                x: 1,
                y: 0,
                width: 2,
                height: 2,
            },
        )
        .unwrap();
        assert_eq!(view.row(0), &[4, 5, 6, 7, 8, 9, 10, 11]);
        assert_eq!(view.row(1), &[16, 17, 18, 19, 20, 21, 22, 23]);
    }

    #[test]
    fn rejects_out_of_bounds_and_overflowing_rectangles() {
        assert_eq!(
            CropRect {
                x: u32::MAX,
                y: 0,
                width: 2,
                height: 1
            }
            .validate(10, 10),
            Err(PixelError::InvalidCrop)
        );
    }

    #[test]
    fn resolves_normalized_coordinates_against_oriented_dimensions() {
        let rect = resolve_crop_region(
            CropRegion::Normalized {
                left: 0.25,
                top: 0.2,
                width: 0.5,
                height: 0.4,
            },
            400,
            300,
            None,
            AspectMismatchPolicy::Reject,
        )
        .unwrap();
        assert_eq!(
            rect,
            CropRect {
                x: 100,
                y: 60,
                width: 200,
                height: 120
            }
        );
    }

    #[test]
    fn creates_largest_centered_region() {
        let rect = resolve_crop_region(
            CropRegion::Centered { aspect_ratio: 1.0 },
            400,
            300,
            None,
            AspectMismatchPolicy::Reject,
        )
        .unwrap();
        assert_eq!(
            rect,
            CropRect {
                x: 50,
                y: 0,
                width: 300,
                height: 300
            }
        );
    }

    #[test]
    fn adjusts_crop_to_exact_output_ratio() {
        let rect = resolve_crop_region(
            CropRegion::Pixels(CropRect {
                x: 0,
                y: 0,
                width: 1000,
                height: 667,
            }),
            1000,
            667,
            Some((1920, 1080)),
            AspectMismatchPolicy::AdjustCrop,
        )
        .unwrap();
        assert_eq!(
            (rect.x, rect.y, rect.width, rect.height),
            (0, 52, 1000, 563)
        );
        let ratio_error = (rect.width as f64 / rect.height as f64 / (16.0 / 9.0) - 1.0).abs();
        assert!(ratio_error < 0.002);
    }

    #[test]
    fn rejects_material_aspect_mismatch() {
        assert_eq!(
            resolve_crop_region(
                CropRegion::Pixels(CropRect::full(1000, 1000)),
                1000,
                1000,
                Some((16, 9)),
                AspectMismatchPolicy::Reject,
            ),
            Err(PixelError::AspectMismatch)
        );
    }

    #[test]
    fn adjusts_for_arbitrary_output_dimensions_at_pixel_precision() {
        let rect = resolve_crop_region(
            CropRegion::Pixels(CropRect::full(100, 100)),
            100,
            100,
            Some((101, 99)),
            AspectMismatchPolicy::AdjustCrop,
        )
        .unwrap();
        assert_eq!(
            rect,
            CropRect {
                x: 0,
                y: 1,
                width: 100,
                height: 98
            }
        );
    }
}
