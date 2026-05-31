cmake_minimum_required(VERSION 3.14)
project(qjsbridge C)

set(CMAKE_C_STANDARD 11)

file(GLOB QJS_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/quickjs.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libunicode.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libregexp.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/cutils.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge/qjs_bridge.c"
)

add_library(qjsbridge SHARED ${QJS_SOURCES})
target_include_directories(qjsbridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge"
)
target_compile_definitions(qjsbridge PRIVATE
  CONFIG_VERSION="2024-01-13"
  CONFIG_BIGNUM
)
