#include <android/bitmap.h>
#include <dlfcn.h>
#include <jni.h>
#include <link.h>

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

struct FfiCropOptions {
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
};

struct FfiCropResult {
  int32_t status;
  uint32_t reason;
  size_t path_length;
  uint8_t is_managed;
  uint8_t reserved[7];
};

using CropRgba = FfiCropResult (*)(
    const uint8_t *, size_t, uint32_t, uint32_t, size_t, const uint8_t *,
    size_t, const uint8_t *, size_t, const FfiCropOptions *, uint8_t *, size_t);

struct SymbolSearch {
  CropRgba function = nullptr;
};

static int find_symbol(dl_phdr_info *info, size_t, void *context) {
  auto *search = static_cast<SymbolSearch *>(context);
  if (info->dlpi_name == nullptr) return 0;
  const std::string path(info->dlpi_name);
  if (path.find("file_image_cropper_native") == std::string::npos &&
      path.find("libfile_image_cropper.so") == std::string::npos) {
    return 0;
  }
  void *handle = dlopen(info->dlpi_name, RTLD_NOW | RTLD_LOCAL);
  if (handle != nullptr) {
    search->function = reinterpret_cast<CropRgba>(
        dlsym(handle, "file_image_cropper_crop_rgba"));
  }
  return search->function == nullptr ? 0 : 1;
}

static CropRgba resolve_crop_rgba() {
  auto function = reinterpret_cast<CropRgba>(
      dlsym(RTLD_DEFAULT, "file_image_cropper_crop_rgba"));
  if (function != nullptr) return function;
  SymbolSearch search;
  dl_iterate_phdr(find_symbol, &search);
  return search.function;
}

static std::vector<uint8_t> byte_array(JNIEnv *env, jbyteArray value) {
  if (value == nullptr) return {};
  const jsize length = env->GetArrayLength(value);
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  if (length > 0) {
    env->GetByteArrayRegion(value, 0, length,
                            reinterpret_cast<jbyte *>(bytes.data()));
  }
  return bytes;
}

static jobjectArray string_result(JNIEnv *env, int status, uint32_t reason,
                                  const std::string &path, bool managed) {
  jclass string_class = env->FindClass("java/lang/String");
  jobjectArray values = env->NewObjectArray(4, string_class, nullptr);
  const std::string status_string = std::to_string(status);
  const std::string reason_string = std::to_string(reason);
  env->SetObjectArrayElement(values, 0, env->NewStringUTF(status_string.c_str()));
  env->SetObjectArrayElement(values, 1, env->NewStringUTF(reason_string.c_str()));
  env->SetObjectArrayElement(values, 2, env->NewStringUTF(path.c_str()));
  env->SetObjectArrayElement(values, 3,
                             env->NewStringUTF(managed ? "true" : "false"));
  return values;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_evgenyuliganets_file_1image_1cropper_FileImageCropperPlugin_nativeCropBitmap(
    JNIEnv *env, jclass, jobject bitmap, jbyteArray output_path,
    jbyteArray managed_root, jint region_type, jdoubleArray region_values,
    jintArray option_values) {
  AndroidBitmapInfo info{};
  if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS ||
      info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {
    return string_result(env, 5, 8, "", false);
  }
  void *pixels = nullptr;
  if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS) {
    return string_result(env, 4, 0, "", false);
  }

  CropRgba crop = resolve_crop_rgba();
  if (crop == nullptr) {
    AndroidBitmap_unlockPixels(env, bitmap);
    return string_result(env, 255, 0, "", false);
  }

  jdouble region[4]{};
  jint options[12]{};
  if (env->GetArrayLength(region_values) != 4 ||
      env->GetArrayLength(option_values) != 12) {
    AndroidBitmap_unlockPixels(env, bitmap);
    return string_result(env, 5, 0, "", false);
  }
  env->GetDoubleArrayRegion(region_values, 0, 4, region);
  env->GetIntArrayRegion(option_values, 0, 12, options);
  const auto output = byte_array(env, output_path);
  const auto root = byte_array(env, managed_root);
  const FfiCropOptions ffi_options{
      static_cast<uint32_t>(region_type), static_cast<uint32_t>(options[0]),
      region[0], region[1], region[2], region[3],
      static_cast<uint32_t>(options[1]), static_cast<uint32_t>(options[2]),
      static_cast<uint32_t>(options[3]), static_cast<uint32_t>(options[4]),
      static_cast<uint32_t>(options[5]), static_cast<uint32_t>(options[6]),
      static_cast<uint32_t>(options[7]), static_cast<uint32_t>(options[8]),
      static_cast<uint32_t>(options[9]), static_cast<uint32_t>(options[10]),
      static_cast<uint32_t>(options[11])};
  std::vector<uint8_t> result_path(65536);
  const size_t pixel_length = static_cast<size_t>(info.stride) * info.height;
  const FfiCropResult result = crop(
      static_cast<const uint8_t *>(pixels), pixel_length, info.width, info.height,
      info.stride, output.empty() ? nullptr : output.data(), output.size(),
      root.empty() ? nullptr : root.data(), root.size(), &ffi_options,
      result_path.data(), result_path.size());
  AndroidBitmap_unlockPixels(env, bitmap);
  const std::string path(result.status == 0
                             ? reinterpret_cast<char *>(result_path.data())
                             : "",
                         result.status == 0 ? result.path_length : 0);
  return string_result(env, result.status, result.reason, path,
                       result.is_managed != 0);
}
