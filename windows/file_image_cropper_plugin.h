#ifndef FLUTTER_PLUGIN_FILE_IMAGE_CROPPER_PLUGIN_H_
#define FLUTTER_PLUGIN_FILE_IMAGE_CROPPER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace file_image_cropper {

class FileImageCropperPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FileImageCropperPlugin();
  ~FileImageCropperPlugin() override;

  FileImageCropperPlugin(const FileImageCropperPlugin&) = delete;
  FileImageCropperPlugin& operator=(const FileImageCropperPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace file_image_cropper

#endif  // FLUTTER_PLUGIN_FILE_IMAGE_CROPPER_PLUGIN_H_
