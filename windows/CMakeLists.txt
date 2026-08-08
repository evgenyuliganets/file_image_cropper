cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "file_image_cropper")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "file_image_cropper_plugin")
list(APPEND PLUGIN_SOURCES
  "file_image_cropper_plugin.cpp"
  "file_image_cropper_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/file_image_cropper/file_image_cropper_plugin_c_api.h"
  "file_image_cropper_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  windowscodecs
  ole32
)

set(file_image_cropper_bundled_libraries "" PARENT_SCOPE)
