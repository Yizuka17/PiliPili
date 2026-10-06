#ifndef RUNNER_WINDOWS_BRIGHTNESS_H_
#define RUNNER_WINDOWS_BRIGHTNESS_H_
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

// Built-in panels expose brightness through WMI; external displays use the
// screen_brightness plugin's DDC/CI path instead.
class WindowsBrightness {
 public:
  WindowsBrightness(flutter::BinaryMessenger* messenger, HWND view);
  ~WindowsBrightness();
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
