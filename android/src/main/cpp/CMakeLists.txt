cmake_minimum_required(VERSION 3.10)
project(file_image_cropper_heic_bridge LANGUAGES CXX)

add_library(file_image_cropper_heic_bridge SHARED heic_bridge.cpp)
target_link_options(
  file_image_cropper_heic_bridge
  PRIVATE
  "-Wl,-z,max-page-size=16384"
  "-Wl,-z,common-page-size=16384"
)
find_library(log-lib log)
find_library(jnigraphics-lib jnigraphics)
find_library(dl-lib dl)
target_link_libraries(
  file_image_cropper_heic_bridge
  ${log-lib}
  ${jnigraphics-lib}
  ${dl-lib}
)
