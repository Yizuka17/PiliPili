#include "windows_integrations.h"
#include <SystemMediaTransportControlsInterop.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <iostream>
#include <map>
#include <vector>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <future>

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
    if (!messenger.Call("pilipili/windows_input", "showKeyboardIfHidden", Value(), &shown) || shown) return 3;
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
    // A self-generated 2x2 PNG must survive the channel and WinRT stream bridge.
    const std::vector<uint8_t> png{
      0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,
      0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x02,0x08,0x02,0x00,0x00,0x00,0xfd,0xd4,0x9a,0x73,
      0x00,0x00,0x00,0x12,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0x34,0xee,0x38,0xc3,0xc0,0xc0,
      0xc0,0xc4,0x00,0x06,0x00,0x11,0xe5,0x01,0x8b,0xae,0xeb,0xe6,0x82,0x00,0x00,0x00,0x00,
      0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82};
    if (!messenger.Call("pilipili/smtc", "update", Value(flutter::EncodableMap{
        {Value("title"), Value("Test title")}, {Value("artist"), Value("Test author")},
        {Value("artwork"), Value("file:///cover.webp")}, {Value("artworkBytes"), Value(png)},
        {Value("playing"), Value(true)}, {Value("canSkip"), Value(true)},
        {Value("durationMs"), Value(int64_t{100000})}, {Value("positionMs"), Value(int64_t{12000})},
    }))) return 10;
    const auto thumbnail = controls.DisplayUpdater().Thumbnail();
    if (!thumbnail) return 11;
    auto read = std::async(std::launch::async, [thumbnail] {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      using namespace winrt::Windows::Storage::Streams;
      std::vector<uint8_t> result;
      {
        const auto stream = thumbnail.OpenReadAsync().get();
        DataReader reader(stream);
        reader.LoadAsync(static_cast<uint32_t>(stream.Size())).get();
        result.resize(reader.UnconsumedBufferLength());
        reader.ReadBytes(result);
      }
      winrt::uninit_apartment();
      return result;
    });
    if (read.get() != png) return 12;
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
  std::cout << "Native SMTC metadata, PNG artwork stream, transport commands, disable and cleanup passed; background keyboard request rejected\n";
  return 0;
}
