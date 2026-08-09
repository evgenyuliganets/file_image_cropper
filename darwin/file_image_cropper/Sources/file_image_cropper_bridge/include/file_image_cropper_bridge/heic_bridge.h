#ifndef FILE_IMAGE_CROPPER_HEIC_BRIDGE_H
#define FILE_IMAGE_CROPPER_HEIC_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint32_t region_type;
  uint32_t aspect_policy;
  double region_a;
  double region_b;
  double region_c;
  double region_d;
  uint32_t output_width;
  uint32_t output_height;
  uint32_t resize_filter;
  uint32_t output_format;
  uint32_t jpeg_quality;
  uint32_t jpeg_background_red;
  uint32_t jpeg_background_green;
  uint32_t jpeg_background_blue;
  uint32_t webp_lossless;
  uint32_t webp_quality;
  uint32_t overwrite;
} FICCropOptions;

int32_t fic_crop_rgba(
    const uint8_t *pixels,
    size_t pixels_length,
    uint32_t width,
    uint32_t height,
    size_t stride,
    const uint8_t *output_path,
    size_t output_path_length,
    const uint8_t *managed_root,
    size_t managed_root_length,
    const FICCropOptions *options,
    uint8_t *result_path,
    size_t result_path_capacity,
    size_t *result_path_length,
    uint8_t *is_managed,
    uint32_t *reason);

#endif
