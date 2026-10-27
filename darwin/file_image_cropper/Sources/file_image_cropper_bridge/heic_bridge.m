#import <Foundation/Foundation.h>
#import <dlfcn.h>

#import "./include/file_image_cropper_bridge/heic_bridge.h"

typedef struct {
  int32_t status;
  uint32_t reason;
  size_t path_length;
  uint8_t is_managed;
  uint8_t reserved[7];
} FfiCropResult;

typedef FfiCropResult (*FICCropRgba)(
    const uint8_t *, size_t, uint32_t, uint32_t, size_t, const uint8_t *,
    size_t, const uint8_t *, size_t, const FICCropOptions *, uint8_t *, size_t);

static FICCropRgba resolveCropRgba(void) {
  FICCropRgba function = (FICCropRgba)dlsym(RTLD_DEFAULT,
                                             "file_image_cropper_crop_rgba");
  if (function != NULL) return function;

  NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath;
  if (frameworks == nil) return NULL;
  NSDirectoryEnumerator<NSString *> *files =
      [NSFileManager.defaultManager enumeratorAtPath:frameworks];
  for (NSString *relativePath in files) {
    NSString *name = relativePath.lastPathComponent;
    if ([name rangeOfString:@"file_image_cropper_native"].location == NSNotFound &&
        ![name isEqualToString:@"libfile_image_cropper.dylib"]) {
      continue;
    }
    NSString *path = [frameworks stringByAppendingPathComponent:relativePath];
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) continue;
    function = (FICCropRgba)dlsym(handle, "file_image_cropper_crop_rgba");
    if (function != NULL) return function;
  }
  return NULL;
}

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
    uint32_t *reason) {
  FICCropRgba crop = resolveCropRgba();
  if (crop == NULL) return 255;
  FfiCropResult result = crop(
      pixels, pixels_length, width, height, stride, output_path,
      output_path_length, managed_root, managed_root_length, options,
      result_path, result_path_capacity);
  if (result_path_length != NULL) *result_path_length = result.path_length;
  if (is_managed != NULL) *is_managed = result.is_managed;
  if (reason != NULL) *reason = result.reason;
  return result.status;
}
