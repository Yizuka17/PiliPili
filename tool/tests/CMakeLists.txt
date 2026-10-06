cmake_minimum_required(VERSION 3.14)
project(pili_touch_input_test LANGUAGES CXX)

get_filename_component(PILI_WORKSPACE "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(EPHEMERAL "${PILI_WORKSPACE}/windows/flutter/ephemeral")
add_executable(windows_touch_input_test
  windows_touch_input_test.cpp
  "${PILI_WORKSPACE}/windows/runner/windows_touch_input.cpp"
  "${PILI_WORKSPACE}/windows/runner/windows_brightness.cpp")
target_compile_features(windows_touch_input_test PRIVATE cxx_std_17)
target_compile_definitions(windows_touch_input_test PRIVATE UNICODE _UNICODE NOMINMAX _HAS_EXCEPTIONS=0)
target_compile_options(windows_touch_input_test PRIVATE /W4 /WX /EHsc /wd4100)
target_include_directories(windows_touch_input_test PRIVATE
  "${PILI_WORKSPACE}/windows/runner"
  "${EPHEMERAL}/cpp_client_wrapper/include"
  "${EPHEMERAL}")
target_link_libraries(windows_touch_input_test PRIVATE user32 comctl32 wbemuuid ole32 oleaut32
  "${PILI_WORKSPACE}/build/windows/x64/flutter/$<CONFIG>/flutter_wrapper_app.lib"
  "${EPHEMERAL}/flutter_windows.dll.lib")
add_custom_command(TARGET windows_touch_input_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${EPHEMERAL}/flutter_windows.dll"
  "$<TARGET_FILE_DIR:windows_touch_input_test>/flutter_windows.dll")
