cmake_minimum_required(VERSION 3.18.1)
project(lifeos_fasttext LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(
    lifeos_fasttext
    SHARED
    lifeos_fasttext_ffi.cpp
)

# Optimize for small binary size, vectorization, and 16KB page-size alignment (Android 15+ Play requirement)
target_compile_options(lifeos_fasttext PRIVATE -O3 -ffunction-sections -fdata-sections -fvisibility=hidden)
target_link_options(lifeos_fasttext PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
