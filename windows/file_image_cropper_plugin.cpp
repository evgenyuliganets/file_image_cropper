#include "file_image_cropper_plugin.h"

#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <climits>
#include <limits>
#include <new>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include "platform_bridge.h"

namespace file_image_cropper {
namespace {

using Microsoft::WRL::ComPtr;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResult = flutter::MethodResult<EncodableValue>;

constexpr char kChannelName[] = "file_image_cropper/heic";
constexpr char kHelpUri[] = "https://apps.microsoft.com/detail/9pmmsr1cgpwg";
constexpr size_t kMaximumPixelBytes = 512ULL * 1024ULL * 1024ULL;

struct Request {
  std::string input_path;
  std::optional<std::string> output_path;
  std::string managed_root;
  FfiCropOptions options{};
};

struct WicImage {
  uint32_t width = 0;
  uint32_t height = 0;
  size_t stride = 0;
  std::vector<uint8_t> pixels;
};

struct OperationError {
  std::string code;
  std::string message;
  bool codec_unavailable = false;
};

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

bool ReadString(const EncodableMap& map, const char* key, std::string* value) {
  const EncodableValue* encoded = Lookup(map, key);
  const auto* string = encoded == nullptr ? nullptr : std::get_if<std::string>(encoded);
  if (string == nullptr) return false;
  *value = *string;
  return true;
}

bool ReadOptionalString(const EncodableMap& map, const char* key,
                        std::optional<std::string>* value) {
  const EncodableValue* encoded = Lookup(map, key);
  if (encoded == nullptr || std::holds_alternative<std::monostate>(*encoded)) {
    *value = std::nullopt;
    return true;
  }
  const auto* string = std::get_if<std::string>(encoded);
  if (string == nullptr) return false;
  *value = *string;
  return true;
}

bool ReadInt(const EncodableMap& map, const char* key, uint32_t* value) {
  const EncodableValue* encoded = Lookup(map, key);
  if (encoded == nullptr) return false;
  int64_t number = -1;
  if (const auto* int32 = std::get_if<int32_t>(encoded)) number = *int32;
  if (const auto* int64 = std::get_if<int64_t>(encoded)) number = *int64;
  if (number < 0 || static_cast<uint64_t>(number) > UINT32_MAX) return false;
  *value = static_cast<uint32_t>(number);
  return true;
}

bool ReadDouble(const EncodableMap& map, const char* key, double* value) {
  const EncodableValue* encoded = Lookup(map, key);
  if (encoded == nullptr) return false;
  if (const auto* number = std::get_if<double>(encoded)) {
    *value = *number;
    return true;
  }
  if (const auto* int32 = std::get_if<int32_t>(encoded)) {
    *value = static_cast<double>(*int32);
    return true;
  }
  if (const auto* int64 = std::get_if<int64_t>(encoded)) {
    *value = static_cast<double>(*int64);
    return true;
  }
  return false;
}

bool ReadBool(const EncodableMap& map, const char* key, uint32_t* value) {
  const EncodableValue* encoded = Lookup(map, key);
  const auto* boolean = encoded == nullptr ? nullptr : std::get_if<bool>(encoded);
  if (boolean == nullptr) return false;
  *value = *boolean ? 1U : 0U;
  return true;
}

bool ParseCropRequest(const EncodableMap& map, Request* request) {
  return ReadString(map, "inputPath", &request->input_path) &&
         ReadOptionalString(map, "outputPath", &request->output_path) &&
         ReadString(map, "managedRoot", &request->managed_root) &&
         ReadInt(map, "regionType", &request->options.region_type) &&
         ReadInt(map, "aspectPolicy", &request->options.aspect_policy) &&
         ReadDouble(map, "regionA", &request->options.region_a) &&
         ReadDouble(map, "regionB", &request->options.region_b) &&
         ReadDouble(map, "regionC", &request->options.region_c) &&
         ReadDouble(map, "regionD", &request->options.region_d) &&
         ReadInt(map, "outputWidth", &request->options.output_width) &&
         ReadInt(map, "outputHeight", &request->options.output_height) &&
         ReadInt(map, "resizeFilter", &request->options.resize_filter) &&
         ReadInt(map, "outputFormat", &request->options.output_format) &&
         ReadInt(map, "jpegQuality", &request->options.jpeg_quality) &&
         ReadInt(map, "jpegBackgroundRed", &request->options.jpeg_background_red) &&
         ReadInt(map, "jpegBackgroundGreen", &request->options.jpeg_background_green) &&
         ReadInt(map, "jpegBackgroundBlue", &request->options.jpeg_background_blue) &&
         ReadBool(map, "webpLossless", &request->options.webp_lossless) &&
         ReadInt(map, "webpQuality", &request->options.webp_quality) &&
         ReadBool(map, "overwrite", &request->options.overwrite);
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                          value.data(),
                                          static_cast<int>(value.size()),
                                          nullptr, 0);
  if (length <= 0) return {};
  std::wstring wide(static_cast<size_t>(length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), wide.data(),
                          length) != length) {
    return {};
  }
  return wide;
}

bool IsMissingCodec(HRESULT result) {
  return result == WINCODEC_ERR_COMPONENTNOTFOUND ||
         result == WINCODEC_ERR_UNKNOWNIMAGEFORMAT ||
         result == REGDB_E_CLASSNOTREG;
}

std::optional<OperationError> ReadWicImage(const std::string& path,
                                           bool decode_pixels,
                                           WicImage* image) {
  const std::wstring wide_path = Utf8ToWide(path);
  if (wide_path.empty()) {
    return OperationError{"invalid_path", "The HEIC path is not valid UTF-8."};
  }
  ComPtr<IWICImagingFactory> factory;
  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&factory));
  if (FAILED(status)) {
    return OperationError{"heic_codec_unavailable",
                          "Windows Imaging Component is unavailable.", true};
  }
  ComPtr<IWICBitmapDecoder> decoder;
  status = factory->CreateDecoderFromFilename(
      wide_path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
      &decoder);
  if (FAILED(status)) {
    if (IsMissingCodec(status)) {
      return OperationError{
          "heic_codec_unavailable",
          "Microsoft HEIF/HEVC image extensions are not installed or cannot "
          "decode this HEIC file.",
          true};
    }
    return OperationError{"heic_decode", "WIC could not open the HEIC file."};
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  status = decoder->GetFrame(0, &frame);
  if (FAILED(status)) {
    return OperationError{"heic_decode", "WIC could not read the HEIC frame."};
  }
  UINT width = 0;
  UINT height = 0;
  status = frame->GetSize(&width, &height);
  if (FAILED(status) || width == 0 || height == 0) {
    return OperationError{"heic_dimensions", "The HEIC dimensions are invalid."};
  }
  image->width = width;
  image->height = height;
  if (!decode_pixels) return std::nullopt;

  const uint64_t stride64 = static_cast<uint64_t>(width) * 4ULL;
  const uint64_t bytes64 = stride64 * static_cast<uint64_t>(height);
  if (stride64 > UINT_MAX || bytes64 > kMaximumPixelBytes ||
      bytes64 > UINT_MAX) {
    return OperationError{"heic_dimensions", "The HEIC image is too large."};
  }
  ComPtr<IWICFormatConverter> converter;
  status = factory->CreateFormatConverter(&converter);
  if (SUCCEEDED(status)) {
    status = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom);
  }
  if (FAILED(status)) {
    if (IsMissingCodec(status)) {
      return OperationError{
          "heic_codec_unavailable",
          "Microsoft HEIF/HEVC image extensions cannot decode this HEIC "
          "pixel format.",
          true};
    }
    return OperationError{"heic_decode", "WIC could not convert HEIC to RGBA8."};
  }
  image->stride = static_cast<size_t>(stride64);
  try {
    image->pixels.resize(static_cast<size_t>(bytes64));
  } catch (const std::bad_alloc&) {
    return OperationError{"heic_memory", "Unable to allocate the HEIC pixel buffer."};
  }
  status = converter->CopyPixels(nullptr, static_cast<UINT>(stride64),
                                 static_cast<UINT>(bytes64),
                                 image->pixels.data());
  if (FAILED(status)) {
    return OperationError{"heic_decode", "WIC failed while decoding HEIC pixels."};
  }
  return std::nullopt;
}

FileImageCropperCropRgba ResolveCropRgba() {
#if defined(_M_ARM64)
  HMODULE module = GetModuleHandleW(
      L"file_image_cropper_native_windows_arm64.dll");
#else
  HMODULE module = GetModuleHandleW(
      L"file_image_cropper_native_windows_x64.dll");
#endif
  if (module == nullptr) return nullptr;
  return reinterpret_cast<FileImageCropperCropRgba>(
      GetProcAddress(module, "file_image_cropper_crop_rgba"));
}

void ReturnError(std::unique_ptr<MethodResult> result,
                 const OperationError& error) {
  if (error.codec_unavailable) {
    EncodableMap details;
    details[EncodableValue("helpUri")] = EncodableValue(kHelpUri);
    result->Error(error.code, error.message, EncodableValue(details));
  } else {
    result->Error(error.code, error.message);
  }
}

void InspectOnWorker(std::string input_path,
                     std::unique_ptr<MethodResult> result) {
  const HRESULT com_status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  WicImage image;
  const auto error = ReadWicImage(input_path, false, &image);
  if (error) {
    ReturnError(std::move(result), *error);
  } else {
    EncodableMap response;
    response[EncodableValue("width")] =
        EncodableValue(static_cast<int64_t>(image.width));
    response[EncodableValue("height")] =
        EncodableValue(static_cast<int64_t>(image.height));
    result->Success(EncodableValue(response));
  }
  if (SUCCEEDED(com_status)) CoUninitialize();
}

void CropOnWorker(Request request, std::unique_ptr<MethodResult> result) {
  const HRESULT com_status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  WicImage image;
  const auto error = ReadWicImage(request.input_path, true, &image);
  if (error) {
    ReturnError(std::move(result), *error);
    if (SUCCEEDED(com_status)) CoUninitialize();
    return;
  }
  FileImageCropperCropRgba crop = ResolveCropRgba();
  if (crop == nullptr) {
    ReturnError(std::move(result),
                OperationError{"native_unavailable",
                               "The bundled Rust RGBA bridge is unavailable."});
    if (SUCCEEDED(com_status)) CoUninitialize();
    return;
  }
  const std::string output = request.output_path.value_or("");
  std::vector<uint8_t> result_path(65536);
  const FfiCropResult native_result = crop(
      image.pixels.data(), image.pixels.size(), image.width, image.height,
      image.stride,
      output.empty() ? nullptr
                     : reinterpret_cast<const uint8_t*>(output.data()),
      output.size(),
      reinterpret_cast<const uint8_t*>(request.managed_root.data()),
      request.managed_root.size(), &request.options, result_path.data(),
      result_path.size());
  if (native_result.status != 0) {
    ReturnError(std::move(result),
                OperationError{"native_" + std::to_string(native_result.status),
                               "Rust crop failed (reason " +
                                   std::to_string(native_result.reason) + ")."});
  } else {
    EncodableMap response;
    response[EncodableValue("path")] = EncodableValue(std::string(
        reinterpret_cast<const char*>(result_path.data()),
        native_result.path_length));
    response[EncodableValue("isManaged")] =
        EncodableValue(native_result.is_managed != 0);
    result->Success(EncodableValue(response));
  }
  if (SUCCEEDED(com_status)) CoUninitialize();
}

}  // namespace

void FileImageCropperPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<FileImageCropperPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

FileImageCropperPlugin::FileImageCropperPlugin() = default;
FileImageCropperPlugin::~FileImageCropperPlugin() = default;

void FileImageCropperPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<MethodResult> result) {
  const auto* arguments = method_call.arguments() == nullptr
                              ? nullptr
                              : std::get_if<EncodableMap>(method_call.arguments());
  if (arguments == nullptr) {
    result->Error("invalid_arguments", "Expected a method argument map.");
    return;
  }
  if (method_call.method_name() == "inspectHeic") {
    std::string input_path;
    if (!ReadString(*arguments, "inputPath", &input_path)) {
      result->Error("invalid_arguments", "Missing inputPath.");
      return;
    }
    std::thread(InspectOnWorker, std::move(input_path), std::move(result)).detach();
    return;
  }
  if (method_call.method_name() == "cropHeic") {
    Request request;
    if (!ParseCropRequest(*arguments, &request)) {
      result->Error("invalid_arguments", "Invalid HEIC crop arguments.");
      return;
    }
    std::thread(CropOnWorker, std::move(request), std::move(result)).detach();
    return;
  }
  result->NotImplemented();
}

}  // namespace file_image_cropper
