use crate::crop::{CropRect, crop_view, materialize_crop};
use crate::pixel::{PixelBuffer, PixelError, PixelLimits, PixelView};
use crate::resize::{ResizeFilter, resize};
use crate::rotate::{Orientation, normalize_orientation, source_crop_for_oriented_rect};
use crate::threading::{ParallelExecutor, shared_executor};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ResizeSpec {
    pub width: u32,
    pub height: u32,
    pub filter: ResizeFilter,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PixelProcessRequest {
    pub orientation: Orientation,
    /// Crop coordinates apply after orientation normalization.
    pub crop: Option<CropRect>,
    pub resize: Option<ResizeSpec>,
    pub limits: PixelLimits,
}

impl Default for PixelProcessRequest {
    fn default() -> Self {
        Self {
            orientation: Orientation::Normal,
            crop: None,
            resize: None,
            limits: PixelLimits::default(),
        }
    }
}

pub fn process_pixels_shared(
    input: PixelBuffer,
    request: PixelProcessRequest,
) -> Result<PixelBuffer, PixelError> {
    process_pixels(input, request, shared_executor())
}

pub fn process_pixels(
    input: PixelBuffer,
    request: PixelProcessRequest,
    executor: Option<&ParallelExecutor>,
) -> Result<PixelBuffer, PixelError> {
    if request.orientation == Orientation::Normal {
        let crop_is_identity = request
            .crop
            .is_none_or(|rect| rect == CropRect::full(input.width(), input.height()));
        let resize_is_identity = request
            .resize
            .is_none_or(|spec| spec.width == input.width() && spec.height == input.height());
        if crop_is_identity && resize_is_identity {
            return Ok(input);
        }
        return finish_view(input.view(), request, executor);
    }

    let oriented_input = if let Some(rect) = request.crop {
        let source_crop = source_crop_for_oriented_rect(
            input.width(),
            input.height(),
            request.orientation,
            rect,
        )?;
        crop_view(input.view(), source_crop)?
    } else {
        input.view()
    };
    let oriented = normalize_orientation(
        oriented_input,
        request.orientation,
        request.limits,
        executor,
    )?;
    drop(input);
    let resize_is_identity = request
        .resize
        .is_none_or(|spec| spec.width == oriented.width() && spec.height == oriented.height());
    if resize_is_identity {
        return Ok(oriented);
    }
    finish_view(
        oriented.view(),
        PixelProcessRequest {
            crop: None,
            ..request
        },
        executor,
    )
}

fn finish_view(
    mut view: PixelView<'_>,
    request: PixelProcessRequest,
    executor: Option<&ParallelExecutor>,
) -> Result<PixelBuffer, PixelError> {
    if let Some(rect) = request.crop {
        view = crop_view(view, rect)?;
    }
    if let Some(spec) = request.resize {
        if spec.width == view.width() && spec.height == view.height() {
            return materialize_crop(view, request.limits, executor);
        }
        return resize(
            view,
            spec.width,
            spec.height,
            spec.filter,
            request.limits,
            executor,
        );
    }
    materialize_crop(view, request.limits, executor)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn labeled_input() -> PixelBuffer {
        let data = (1..=6).flat_map(|value| [value, 0, 0, 255]).collect();
        PixelBuffer::new_rgba8(3, 2, data).unwrap()
    }

    #[test]
    fn no_op_preserves_the_owned_buffer() {
        let input = labeled_input();
        let expected = input.clone();
        assert_eq!(
            process_pixels(input, PixelProcessRequest::default(), None).unwrap(),
            expected
        );
    }

    #[test]
    fn orientation_then_crop_then_resize_uses_oriented_coordinates() {
        let output = process_pixels(
            labeled_input(),
            PixelProcessRequest {
                orientation: Orientation::Rotate90Clockwise,
                crop: Some(CropRect {
                    x: 0,
                    y: 1,
                    width: 2,
                    height: 2,
                }),
                resize: Some(ResizeSpec {
                    width: 4,
                    height: 2,
                    filter: ResizeFilter::Nearest,
                }),
                limits: PixelLimits::default(),
            },
            None,
        )
        .unwrap();
        let labels: Vec<_> = output
            .data()
            .chunks_exact(4)
            .map(|pixel| pixel[0])
            .collect();
        assert_eq!(labels, vec![5, 5, 2, 2, 6, 6, 3, 3]);
    }
}
