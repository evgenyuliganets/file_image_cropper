cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "file_image_cropper")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "file_image_cropper_plugin")

add_library(${PLUGIN_NAME} SHARED
  "file_image_cropper_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK ${CMAKE_DL_LIBS})

set(file_image_cropper_bundled_libraries "" PARENT_SCOPE)
