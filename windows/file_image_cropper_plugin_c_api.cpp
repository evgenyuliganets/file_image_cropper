#include "include/file_image_cropper/file_image_cropper_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "file_image_cropper_plugin.h"

void FileImageCropperPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  file_image_cropper::FileImageCropperPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
