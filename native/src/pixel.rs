//! Validated canonical RGBA8 pixel storage and borrowed image views.

use std::fmt;

pub const RGBA_CHANNELS: usize = 4;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PixelLimits {
    pub max_pixels: usize,
    pub max_allocation_bytes: usize,
}

impl Default for PixelLimits {
    fn default() -> Self {
        Self {
            max_pixels: 100_000_000,
            max_allocation_bytes: 512 * 1024 * 1024,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PixelError {
    ZeroDimensions,
    DimensionOverflow,
    BufferSizeMismatch { expected: usize, actual: usize },
    PixelLimitExceeded { pixels: usize, limit: usize },
    AllocationLimitExceeded { bytes: usize, limit: usize },
    AllocationFailed { bytes: usize },
    InvalidCrop,
    AspectMismatch,
    InvalidOrientation(u8),
    InvalidRowLayout,
}

impl fmt::Display for PixelError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroDimensions => formatter.write_str("pixel dimensions must be non-zero"),
            Self::DimensionOverflow => formatter.write_str("pixel dimensions overflow"),
            Self::BufferSizeMismatch { expected, actual } => {
                write!(
                    formatter,
                    "RGBA buffer size is {actual}, expected {expected}"
                )
            }
            Self::PixelLimitExceeded { pixels, limit } => {
                write!(formatter, "pixel count {pixels} exceeds limit {limit}")
            }
            Self::AllocationLimitExceeded { bytes, limit } => {
                write!(formatter, "allocation {bytes} exceeds limit {limit}")
            }
            Self::AllocationFailed { bytes } => {
                write!(formatter, "unable to allocate {bytes} bytes for pixels")
            }
            Self::InvalidCrop => formatter.write_str("crop rectangle is outside image bounds"),
            Self::AspectMismatch => formatter.write_str(
                "crop and output aspect ratios differ; use adjustCrop or stretch to allow it",
            ),
            Self::InvalidOrientation(value) => {
                write!(formatter, "invalid EXIF orientation {value}")
            }
            Self::InvalidRowLayout => formatter.write_str("invalid pixel row layout"),
        }
    }
}

impl std::error::Error for PixelError {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PixelBuffer {
    width: u32,
    height: u32,
    data: Vec<u8>,
}

impl PixelBuffer {
    pub fn new_rgba8(width: u32, height: u32, data: Vec<u8>) -> Result<Self, PixelError> {
        Self::new_rgba8_with_limits(width, height, data, PixelLimits::default())
    }

    pub fn new_rgba8_with_limits(
        width: u32,
        height: u32,
        data: Vec<u8>,
        limits: PixelLimits,
    ) -> Result<Self, PixelError> {
        let expected = allocation_size(width, height, limits)?;
        if data.len() != expected {
            return Err(PixelError::BufferSizeMismatch {
                expected,
                actual: data.len(),
            });
        }
        Ok(Self {
            width,
            height,
            data,
        })
    }

    pub fn allocate(width: u32, height: u32, limits: PixelLimits) -> Result<Self, PixelError> {
        let bytes = allocation_size(width, height, limits)?;
        let mut data = Vec::new();
        data.try_reserve_exact(bytes)
            .map_err(|_| PixelError::AllocationFailed { bytes })?;
        data.resize(bytes, 0);
        Ok(Self {
            width,
            height,
            data,
        })
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn data(&self) -> &[u8] {
        &self.data
    }

    pub fn data_mut(&mut self) -> &mut [u8] {
        &mut self.data
    }

    pub fn view(&self) -> PixelView<'_> {
        PixelView {
            data: &self.data,
            width: self.width,
            height: self.height,
            stride: self.width as usize * RGBA_CHANNELS,
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct PixelView<'a> {
    data: &'a [u8],
    width: u32,
    height: u32,
    stride: usize,
}

impl<'a> PixelView<'a> {
    pub fn width(self) -> u32 {
        self.width
    }

    pub fn height(self) -> u32 {
        self.height
    }

    pub fn stride(self) -> usize {
        self.stride
    }

    pub fn row(self, y: u32) -> &'a [u8] {
        assert!(y < self.height, "row index validated by caller");
        let start = y as usize * self.stride;
        &self.data[start..start + self.width as usize * RGBA_CHANNELS]
    }

    pub(crate) fn crop(self, x: u32, y: u32, width: u32, height: u32) -> Self {
        let offset = y as usize * self.stride + x as usize * RGBA_CHANNELS;
        Self {
            data: &self.data[offset..],
            width,
            height,
            stride: self.stride,
        }
    }
}

pub fn allocation_size(width: u32, height: u32, limits: PixelLimits) -> Result<usize, PixelError> {
    if width == 0 || height == 0 {
        return Err(PixelError::ZeroDimensions);
    }
    let pixels = (width as usize)
        .checked_mul(height as usize)
        .ok_or(PixelError::DimensionOverflow)?;
    if pixels > limits.max_pixels {
        return Err(PixelError::PixelLimitExceeded {
            pixels,
            limit: limits.max_pixels,
        });
    }
    let bytes = pixels
        .checked_mul(RGBA_CHANNELS)
        .ok_or(PixelError::DimensionOverflow)?;
    if bytes > limits.max_allocation_bytes {
        return Err(PixelError::AllocationLimitExceeded {
            bytes,
            limit: limits.max_allocation_bytes,
        });
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_exact_rgba_buffer_size() {
        assert!(PixelBuffer::new_rgba8(2, 2, vec![0; 16]).is_ok());
        assert_eq!(
            PixelBuffer::new_rgba8(2, 2, vec![0; 15]),
            Err(PixelError::BufferSizeMismatch {
                expected: 16,
                actual: 15
            })
        );
    }

    #[test]
    fn enforces_limits_before_allocation() {
        let limits = PixelLimits {
            max_pixels: 4,
            max_allocation_bytes: 16,
        };
        assert!(matches!(
            PixelBuffer::allocate(3, 2, limits),
            Err(PixelError::PixelLimitExceeded { .. })
        ));
        assert_eq!(
            PixelBuffer::allocate(0, 1, limits),
            Err(PixelError::ZeroDimensions)
        );
    }
}
