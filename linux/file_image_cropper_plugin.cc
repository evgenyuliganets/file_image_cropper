#include "include/file_image_cropper/file_image_cropper_plugin.h"

#include <dlfcn.h>
#include <link.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "platform_bridge.h"

#define FILE_IMAGE_CROPPER_PLUGIN(obj)                               \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), file_image_cropper_plugin_get_type(), \
                              FileImageCropperPlugin))

struct _FileImageCropperPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FileImageCropperPlugin, file_image_cropper_plugin,
              g_object_get_type())

namespace {

constexpr char kChannelName[] = "file_image_cropper/heic";
constexpr char kHelpUri[] = "https://github.com/strukturag/libheif";
constexpr size_t kMaximumPixelBytes = 512ULL * 1024ULL * 1024ULL;
constexpr size_t kResultPathCapacity = 65536;

struct heif_context;
struct heif_image_handle;
struct heif_image;
struct heif_decoding_options;
struct heif_reading_options;

struct heif_error {
  int code;
  int subcode;
  const char* message;
};

constexpr int kHeifErrorOk = 0;
constexpr int kHeifErrorDecoderPlugin = 7;
constexpr int kHeifCompressionHevc = 1;
constexpr int kHeifColorspaceRgb = 1;
constexpr int kHeifChromaInterleavedRgba = 11;
constexpr int kHeifChannelInterleaved = 10;

struct HeifApi {
  using ContextAlloc = heif_context* (*)();
  using ContextFree = void (*)(heif_context*);
  using ContextReadFromFile = heif_error (*)(heif_context*, const char*,
                                              const heif_reading_options*);
  using ContextGetPrimaryImageHandle = heif_error (*)(
      heif_context*, heif_image_handle**);
  using ContextSetMaxDecodingThreads = void (*)(heif_context*, int);
  using HaveDecoderForFormat = int (*)(int);
  using ImageHandleRelease = void (*)(const heif_image_handle*);
  using ImageHandleGetDimension = int (*)(const heif_image_handle*);
  using DecodeImage = heif_error (*)(const heif_image_handle*, heif_image**,
                                      int, int,
                                      const heif_decoding_options*);
  using ImageGetPlaneReadonly = const uint8_t* (*)(const heif_image*, int,
                                                    int*);
  using ImageRelease = void (*)(const heif_image*);

  void* library = nullptr;
  ContextAlloc context_alloc = nullptr;
  ContextFree context_free = nullptr;
  ContextReadFromFile context_read_from_file = nullptr;
  ContextGetPrimaryImageHandle context_get_primary_image_handle = nullptr;
  ContextSetMaxDecodingThreads context_set_max_decoding_threads = nullptr;
  HaveDecoderForFormat have_decoder_for_format = nullptr;
  ImageHandleRelease image_handle_release = nullptr;
  ImageHandleGetDimension image_handle_get_width = nullptr;
  ImageHandleGetDimension image_handle_get_height = nullptr;
  DecodeImage decode_image = nullptr;
  ImageGetPlaneReadonly image_get_plane_readonly = nullptr;
  ImageRelease image_release = nullptr;

  HeifApi() = default;
  HeifApi(const HeifApi&) = delete;
  HeifApi& operator=(const HeifApi&) = delete;
  HeifApi(HeifApi&& other) noexcept { *this = std::move(other); }
  HeifApi& operator=(HeifApi&& other) noexcept {
    if (this == &other) return *this;
    if (library != nullptr) dlclose(library);
    library = std::exchange(other.library, nullptr);
    context_alloc = other.context_alloc;
    context_free = other.context_free;
    context_read_from_file = other.context_read_from_file;
    context_get_primary_image_handle = other.context_get_primary_image_handle;
    context_set_max_decoding_threads = other.context_set_max_decoding_threads;
    have_decoder_for_format = other.have_decoder_for_format;
    image_handle_release = other.image_handle_release;
    image_handle_get_width = other.image_handle_get_width;
    image_handle_get_height = other.image_handle_get_height;
    decode_image = other.decode_image;
    image_get_plane_readonly = other.image_get_plane_readonly;
    image_release = other.image_release;
    return *this;
  }
  ~HeifApi() {
    if (library != nullptr) dlclose(library);
  }
};

template <typename T>
T LoadSymbol(void* library, const char* name) {
  return reinterpret_cast<T>(dlsym(library, name));
}

std::optional<HeifApi> LoadHeifApi() {
  HeifApi api;
  api.library = dlopen("libheif.so.1", RTLD_NOW | RTLD_LOCAL);
  if (api.library == nullptr) {
    api.library = dlopen("libheif.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (api.library == nullptr) return std::nullopt;

  api.context_alloc =
      LoadSymbol<HeifApi::ContextAlloc>(api.library, "heif_context_alloc");
  api.context_free =
      LoadSymbol<HeifApi::ContextFree>(api.library, "heif_context_free");
  api.context_read_from_file = LoadSymbol<HeifApi::ContextReadFromFile>(
      api.library, "heif_context_read_from_file");
  api.context_get_primary_image_handle =
      LoadSymbol<HeifApi::ContextGetPrimaryImageHandle>(
          api.library, "heif_context_get_primary_image_handle");
  api.context_set_max_decoding_threads =
      LoadSymbol<HeifApi::ContextSetMaxDecodingThreads>(
          api.library, "heif_context_set_max_decoding_threads");
  api.have_decoder_for_format = LoadSymbol<HeifApi::HaveDecoderForFormat>(
      api.library, "heif_have_decoder_for_format");
  api.image_handle_release = LoadSymbol<HeifApi::ImageHandleRelease>(
      api.library, "heif_image_handle_release");
  api.image_handle_get_width = LoadSymbol<HeifApi::ImageHandleGetDimension>(
      api.library, "heif_image_handle_get_width");
  api.image_handle_get_height = LoadSymbol<HeifApi::ImageHandleGetDimension>(
      api.library, "heif_image_handle_get_height");
  api.decode_image =
      LoadSymbol<HeifApi::DecodeImage>(api.library, "heif_decode_image");
  api.image_get_plane_readonly = LoadSymbol<HeifApi::ImageGetPlaneReadonly>(
      api.library, "heif_image_get_plane_readonly");
  api.image_release =
      LoadSymbol<HeifApi::ImageRelease>(api.library, "heif_image_release");

  if (api.context_alloc == nullptr || api.context_free == nullptr ||
      api.context_read_from_file == nullptr ||
      api.context_get_primary_image_handle == nullptr ||
      api.have_decoder_for_format == nullptr ||
      api.image_handle_release == nullptr ||
      api.image_handle_get_width == nullptr ||
      api.image_handle_get_height == nullptr || api.decode_image == nullptr ||
      api.image_get_plane_readonly == nullptr || api.image_release == nullptr) {
    return std::nullopt;
  }
  return api;
}

struct Request {
  std::string input_path;
  std::optional<std::string> output_path;
  std::string managed_root;
  FfiCropOptions options{};
};

struct DecodedImage {
  const uint8_t* pixels = nullptr;
  uint32_t width = 0;
  uint32_t height = 0;
  size_t stride = 0;
  size_t length = 0;
  heif_image* image = nullptr;
};

struct OperationError {
  std::string code;
  std::string message;
  bool codec_unavailable = false;
};

struct Completion {
  FlMethodCall* method_call;
  std::optional<OperationError> error;
  bool inspect = false;
  uint32_t width = 0;
  uint32_t height = 0;
  std::string path;
  bool is_managed = false;
};

FlValue* Lookup(FlValue* map, const char* key) {
  return fl_value_lookup_string(map, key);
}

bool ReadString(FlValue* map, const char* key, std::string* value) {
  FlValue* encoded = Lookup(map, key);
  if (encoded == nullptr || fl_value_get_type(encoded) != FL_VALUE_TYPE_STRING) {
    return false;
  }
  *value = fl_value_get_string(encoded);
  return true;
}

bool ReadOptionalString(FlValue* map, const char* key,
                        std::optional<std::string>* value) {
  FlValue* encoded = Lookup(map, key);
  if (encoded == nullptr || fl_value_get_type(encoded) == FL_VALUE_TYPE_NULL) {
    *value = std::nullopt;
    return true;
  }
  if (fl_value_get_type(encoded) != FL_VALUE_TYPE_STRING) return false;
  *value = fl_value_get_string(encoded);
  return true;
}

bool ReadInt(FlValue* map, const char* key, uint32_t* value) {
  FlValue* encoded = Lookup(map, key);
  if (encoded == nullptr || fl_value_get_type(encoded) != FL_VALUE_TYPE_INT) {
    return false;
  }
  const int64_t number = fl_value_get_int(encoded);
  if (number < 0 ||
      static_cast<uint64_t>(number) > std::numeric_limits<uint32_t>::max()) {
    return false;
  }
  *value = static_cast<uint32_t>(number);
  return true;
}

bool ReadDouble(FlValue* map, const char* key, double* value) {
  FlValue* encoded = Lookup(map, key);
  if (encoded == nullptr) return false;
  if (fl_value_get_type(encoded) == FL_VALUE_TYPE_FLOAT) {
    *value = fl_value_get_float(encoded);
    return true;
  }
  if (fl_value_get_type(encoded) == FL_VALUE_TYPE_INT) {
    *value = static_cast<double>(fl_value_get_int(encoded));
    return true;
  }
  return false;
}

bool ReadBool(FlValue* map, const char* key, uint32_t* value) {
  FlValue* encoded = Lookup(map, key);
  if (encoded == nullptr || fl_value_get_type(encoded) != FL_VALUE_TYPE_BOOL) {
    return false;
  }
  *value = fl_value_get_bool(encoded) ? 1U : 0U;
  return true;
}

bool ParseCropRequest(FlValue* map, Request* request) {
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
         ReadInt(map, "jpegBackgroundRed",
                 &request->options.jpeg_background_red) &&
         ReadInt(map, "jpegBackgroundGreen",
                 &request->options.jpeg_background_green) &&
         ReadInt(map, "jpegBackgroundBlue",
                 &request->options.jpeg_background_blue) &&
         ReadBool(map, "webpLossless", &request->options.webp_lossless) &&
         ReadInt(map, "webpQuality", &request->options.webp_quality) &&
         ReadBool(map, "overwrite", &request->options.overwrite);
}

std::string HeifMessage(const char* prefix, const heif_error& error) {
  std::string message(prefix);
  if (error.message != nullptr && error.message[0] != '\0') {
    message.append(": ").append(error.message);
  }
  return message;
}

std::optional<OperationError> OpenHeif(
    HeifApi* api, const std::string& path, heif_context** context,
    heif_image_handle** handle) {
  auto loaded = LoadHeifApi();
  if (!loaded ||
      loaded->have_decoder_for_format(kHeifCompressionHevc) == 0) {
    return OperationError{
        "heic_codec_unavailable",
        "Install libheif with an HEVC decoder to read HEIC images.", true};
  }
  *api = std::move(*loaded);
  *context = api->context_alloc();
  if (*context == nullptr) {
    return OperationError{"heic_memory", "Unable to create a libheif context."};
  }
  if (api->context_set_max_decoding_threads != nullptr) {
    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    const int threads = static_cast<int>(
        std::max(1U, std::min(hardware_threads == 0 ? 1U : hardware_threads,
                              8U)));
    api->context_set_max_decoding_threads(*context, threads);
  }
  const heif_error read_error =
      api->context_read_from_file(*context, path.c_str(), nullptr);
  if (read_error.code != kHeifErrorOk) {
    return OperationError{
        read_error.code == kHeifErrorDecoderPlugin ? "heic_codec_unavailable"
                                                   : "heic_decode",
        HeifMessage("libheif could not open the HEIC file", read_error),
        read_error.code == kHeifErrorDecoderPlugin};
  }
  const heif_error handle_error =
      api->context_get_primary_image_handle(*context, handle);
  if (handle_error.code != kHeifErrorOk || *handle == nullptr) {
    return OperationError{
        "heic_decode",
        HeifMessage("libheif could not read the primary image", handle_error)};
  }
  return std::nullopt;
}

std::optional<OperationError> ReadDimensions(
    const HeifApi& api, const heif_image_handle* handle, uint32_t* width,
    uint32_t* height) {
  const int decoded_width = api.image_handle_get_width(handle);
  const int decoded_height = api.image_handle_get_height(handle);
  if (decoded_width <= 0 || decoded_height <= 0) {
    return OperationError{"heic_dimensions", "The HEIC dimensions are invalid."};
  }
  *width = static_cast<uint32_t>(decoded_width);
  *height = static_cast<uint32_t>(decoded_height);
  return std::nullopt;
}

std::optional<OperationError> DecodeRgba(const HeifApi& api,
                                         const heif_image_handle* handle,
                                         DecodedImage* output) {
  const heif_error decode_error = api.decode_image(
      handle, &output->image, kHeifColorspaceRgb,
      kHeifChromaInterleavedRgba, nullptr);
  if (decode_error.code != kHeifErrorOk || output->image == nullptr) {
    return OperationError{
        decode_error.code == kHeifErrorDecoderPlugin
            ? "heic_codec_unavailable"
            : "heic_decode",
        HeifMessage("libheif failed to decode HEIC pixels", decode_error),
        decode_error.code == kHeifErrorDecoderPlugin};
  }
  int stride = 0;
  output->pixels = api.image_get_plane_readonly(
      output->image, kHeifChannelInterleaved, &stride);
  const uint64_t minimum_stride = static_cast<uint64_t>(output->width) * 4ULL;
  if (output->pixels == nullptr || stride <= 0 ||
      static_cast<uint64_t>(stride) < minimum_stride) {
    return OperationError{"heic_decode", "libheif returned an invalid RGBA plane."};
  }
  const uint64_t bytes =
      static_cast<uint64_t>(stride) * static_cast<uint64_t>(output->height);
  if (bytes > kMaximumPixelBytes ||
      bytes > std::numeric_limits<size_t>::max()) {
    return OperationError{"heic_dimensions", "The HEIC image is too large."};
  }
  output->stride = static_cast<size_t>(stride);
  output->length = static_cast<size_t>(bytes);
  return std::nullopt;
}

struct NativeLookup {
  FileImageCropperCropRgba function = nullptr;
  void* library = nullptr;
};

int FindNativeLibrary(dl_phdr_info* info, size_t, void* data) {
  auto* lookup = static_cast<NativeLookup*>(data);
  if (lookup->function != nullptr || info->dlpi_name == nullptr) return 0;
  const std::string path(info->dlpi_name);
  if (path.find("file_image_cropper_native") == std::string::npos &&
      path.find("libfile_image_cropper.so") == std::string::npos) {
    return 0;
  }
  void* library = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) return 0;
  auto function = LoadSymbol<FileImageCropperCropRgba>(
      library, "file_image_cropper_crop_rgba");
  if (function == nullptr) {
    dlclose(library);
    return 0;
  }
  lookup->function = function;
  lookup->library = library;
  return 1;
}

FileImageCropperCropRgba ResolveCropRgba() {
  static const FileImageCropperCropRgba function = [] {
    auto global_function = LoadSymbol<FileImageCropperCropRgba>(
        RTLD_DEFAULT, "file_image_cropper_crop_rgba");
    if (global_function != nullptr) return global_function;
    NativeLookup lookup;
    dl_iterate_phdr(FindNativeLibrary, &lookup);
    // Retain this single extra handle for the process lifetime. Dart's native
    // asset loader owns the same library, and every crop reuses the function.
    return lookup.function;
  }();
  return function;
}

gboolean CompleteOnMainThread(gpointer data) {
  std::unique_ptr<Completion> completion(static_cast<Completion*>(data));
  g_autoptr(FlMethodResponse) response = nullptr;
  if (completion->error) {
    g_autoptr(FlValue) details = nullptr;
    if (completion->error->codec_unavailable) {
      details = fl_value_new_map();
      fl_value_set_string_take(details, "helpUri",
                               fl_value_new_string(kHelpUri));
    }
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        completion->error->code.c_str(), completion->error->message.c_str(),
        details));
  } else {
    g_autoptr(FlValue) result = fl_value_new_map();
    if (completion->inspect) {
      fl_value_set_string_take(
          result, "width",
          fl_value_new_int(static_cast<int64_t>(completion->width)));
      fl_value_set_string_take(
          result, "height",
          fl_value_new_int(static_cast<int64_t>(completion->height)));
    } else {
      fl_value_set_string_take(result, "path",
                               fl_value_new_string(completion->path.c_str()));
      fl_value_set_string_take(result, "isManaged",
                               fl_value_new_bool(completion->is_managed));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  fl_method_call_respond(completion->method_call, response, nullptr);
  g_object_unref(completion->method_call);
  return G_SOURCE_REMOVE;
}

void Dispatch(std::unique_ptr<Completion> completion) {
  g_main_context_invoke(nullptr, CompleteOnMainThread, completion.release());
}

void InspectOnWorker(std::string input_path, FlMethodCall* method_call) {
  auto completion = std::make_unique<Completion>();
  completion->method_call = method_call;
  completion->inspect = true;
  HeifApi api;
  heif_context* context = nullptr;
  heif_image_handle* handle = nullptr;
  completion->error = OpenHeif(&api, input_path, &context, &handle);
  if (!completion->error) {
    completion->error =
        ReadDimensions(api, handle, &completion->width, &completion->height);
  }
  if (handle != nullptr) api.image_handle_release(handle);
  if (context != nullptr) api.context_free(context);
  Dispatch(std::move(completion));
}

void CropOnWorker(Request request, FlMethodCall* method_call) {
  auto completion = std::make_unique<Completion>();
  completion->method_call = method_call;
  HeifApi api;
  heif_context* context = nullptr;
  heif_image_handle* handle = nullptr;
  DecodedImage image;
  completion->error = OpenHeif(&api, request.input_path, &context, &handle);
  if (!completion->error) {
    completion->error =
        ReadDimensions(api, handle, &image.width, &image.height);
  }
  if (!completion->error) {
    completion->error = DecodeRgba(api, handle, &image);
  }
  if (!completion->error) {
    FileImageCropperCropRgba crop = ResolveCropRgba();
    if (crop == nullptr) {
      completion->error = OperationError{
          "native_unavailable", "The bundled Rust RGBA bridge is unavailable."};
    } else {
      const std::string output = request.output_path.value_or("");
      std::vector<uint8_t> result_path(kResultPathCapacity);
      const FfiCropResult native_result = crop(
          image.pixels, image.length, image.width, image.height, image.stride,
          output.empty() ? nullptr
                         : reinterpret_cast<const uint8_t*>(output.data()),
          output.size(),
          reinterpret_cast<const uint8_t*>(request.managed_root.data()),
          request.managed_root.size(), &request.options, result_path.data(),
          result_path.size());
      if (native_result.status != 0) {
        completion->error = OperationError{
            "native_" + std::to_string(native_result.status),
            "Rust crop failed (reason " +
                std::to_string(native_result.reason) + ")."};
      } else if (native_result.path_length > result_path.size()) {
        completion->error = OperationError{
            "native_invalid_result", "Rust returned an invalid output path."};
      } else {
        completion->path.assign(
            reinterpret_cast<const char*>(result_path.data()),
            native_result.path_length);
        completion->is_managed = native_result.is_managed != 0;
      }
    }
  }
  if (image.image != nullptr) api.image_release(image.image);
  if (handle != nullptr) api.image_handle_release(handle);
  if (context != nullptr) api.context_free(context);
  Dispatch(std::move(completion));
}

void HandleMethodCall(FlMethodCall* method_call) {
  const char* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid_arguments",
                                     "Expected a method argument map.", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (std::strcmp(method, "inspectHeic") == 0) {
    std::string input_path;
    if (!ReadString(arguments, "inputPath", &input_path)) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid_arguments",
                                       "Missing inputPath.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    g_object_ref(method_call);
    std::thread(InspectOnWorker, std::move(input_path), method_call).detach();
    return;
  }
  if (std::strcmp(method, "cropHeic") == 0) {
    Request request;
    if (!ParseCropRequest(arguments, &request)) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid_arguments",
                                       "Invalid HEIC crop arguments.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    g_object_ref(method_call);
    std::thread(CropOnWorker, std::move(request), method_call).detach();
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

void MethodCallCallback(FlMethodChannel*, FlMethodCall* method_call,
                        gpointer) {
  HandleMethodCall(method_call);
}

}  // namespace

static void file_image_cropper_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(file_image_cropper_plugin_parent_class)->dispose(object);
}

static void file_image_cropper_plugin_class_init(
    FileImageCropperPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = file_image_cropper_plugin_dispose;
}

static void file_image_cropper_plugin_init(FileImageCropperPlugin*) {}

void file_image_cropper_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FileImageCropperPlugin* plugin = FILE_IMAGE_CROPPER_PLUGIN(
      g_object_new(file_image_cropper_plugin_get_type(), nullptr));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, MethodCallCallback,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(plugin);
}
