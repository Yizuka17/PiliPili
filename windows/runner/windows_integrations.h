#ifndef RUNNER_WINDOWS_INTEGRATIONS_H_
#define RUNNER_WINDOWS_INTEGRATIONS_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <string>
#include <vector>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.UI.ViewManagement.h>

// All channel calls run on the platform thread. SMTC callbacks are marshalled
// back through the HWND before calling Flutter's messenger.
class WindowsIntegrations {
 public:
  WindowsIntegrations(flutter::BinaryMessenger* messenger, HWND parent, HWND view);
  ~WindowsIntegrations();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool Keyboard(bool show);
  void EnsureMediaControls();
  void UpdateMedia(const flutter::EncodableMap& data);
  void SetEnabled(bool enabled);
  HWND parent_;
  HWND view_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> input_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> media_channel_;
  winrt::Windows::UI::ViewManagement::InputPane input_pane_{nullptr};
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token seek_token_{};
  std::string title_;
  std::string artist_;
  std::string artwork_;
  std::vector<uint8_t> artwork_bytes_;
  bool metadata_set_ = false;
};
#endif
