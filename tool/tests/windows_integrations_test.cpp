#include "windows_integrations.h"
#include <SystemMediaTransportControlsInterop.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <iostream>
#include <map>
#include <vector>
#include <winrt/Windows.Foundation.h>

using Value = flutter::EncodableValue;
class Messenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  mutable std::vector<std::string> commands;
  void Send(const std::string&, const uint8_t* data, size_t size,
            flutter::BinaryReply = nullptr) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(data, size);
    if (call) commands.push_back(call->method_name());
  }
  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    if (handler) handlers[channel] = std::move(handler);
    else handlers.erase(channel);
  }
  bool Call(const std::string& channel, const std::string& method, Value argument,
            bool* boolean = nullptr) {
    const auto request = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<Value>(method, std::make_unique<Value>(std::move(argument))));
    bool success = false;
    handlers.at(channel)(request->data(), request->size(),
      [&success, boolean](const uint8_t* data, size_t size) {
        flutter::MethodResultFunctions<Value> result(
          [&success, boolean](const Value* value) {
            success = true;
            if (boolean && value) *boolean = std::get<bool>(*value);
          },
          [](const std::string& code, const std::string&, const Value*) {
            std::cerr << code << '\n';
          }, nullptr);
        flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(data, size, &result);
      });
    return success;
  }
};

int main() {
  winrt::init_apartment(winrt::apartment_type::single_threaded);
  const HWND parent = CreateWindow(L"STATIC", L"Pilipili integration test", WS_OVERLAPPED,
      0, 0, 200, 200, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  const HWND view = CreateWindow(L"STATIC", L"view", WS_CHILD,
      0, 0, 100, 100, parent, nullptr, GetModuleHandle(nullptr), nullptr);
  if (!parent || !view) return 1;
  Messenger messenger;
  {
    WindowsIntegrations integrations(&messenger, parent, view);
    if (!messenger.Call("pilipili/smtc", "setEnabled", Value(false))) return 2;
    bool shown = true;
    if (!messenger.Call("pilipili/windows_input", "showKeyboard", Value(), &shown) || shown) return 3;
    if (!messenger.Call("pilipili/smtc", "update", Value(flutter::EncodableMap{
        {Value("title"), Value("Test title")}, {Value("artist"), Value("Test author")},
        {Value("artwork"), Value("")}, {Value("playing"), Value(true)},
        {Value("canSkip"), Value(true)}, {Value("durationMs"), Value(int64_t{100000})},
        {Value("positionMs"), Value(int64_t{12000})},
    }))) return 4;
    using namespace winrt::Windows::Media;
    SystemMediaTransportControls controls{nullptr};
    const auto interop = winrt::get_activation_factory<SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(parent,
        winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls)));
    if (!controls.IsEnabled() || controls.PlaybackStatus() != MediaPlaybackStatus::Playing ||
        controls.DisplayUpdater().MusicProperties().Title() != L"Test title" ||
        controls.DisplayUpdater().MusicProperties().Artist() != L"Test author") return 5;
    integrations.HandleMessage(WM_APP + 0x351,
        static_cast<WPARAM>(SystemMediaTransportControlsButton::Pause), 0);
    if (messenger.commands.size() != 1 || messenger.commands.front() != "pause") return 6;
    if (!messenger.Call("pilipili/smtc", "setEnabled", Value(false))) return 7;
    integrations.HandleMessage(WM_APP + 0x351,
        static_cast<WPARAM>(SystemMediaTransportControlsButton::Play), 0);
    if (controls.IsEnabled() || messenger.commands.size() != 1) return 8;
  }
  if (!messenger.handlers.empty()) return 9;
  DestroyWindow(parent);
  winrt::uninit_apartment();
  std::cout << "Native SMTC metadata, transport commands, disable and cleanup passed; background keyboard request rejected\n";
  return 0;
}
