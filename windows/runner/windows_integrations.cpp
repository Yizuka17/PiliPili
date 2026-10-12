#include "windows_integrations.h"

#include <inputpaneinterop.h>
#include <SystemMediaTransportControlsInterop.h>
#include <shcore.h>
#include <shlwapi.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <chrono>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {
constexpr UINT kMediaButton = WM_APP + 0x351;
constexpr UINT kMediaSeek = WM_APP + 0x352;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using namespace winrt::Windows::Media;

std::string String(const Map& data, const char* key) {
  const auto it = data.find(Value(key));
  if (it == data.end()) return {};
  const auto value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string{};
}
int64_t Integer(const Map& data, const char* key) {
  const auto it = data.find(Value(key));
  if (it == data.end()) return 0;
  if (const auto value = std::get_if<int64_t>(&it->second)) return *value;
  if (const auto value = std::get_if<int32_t>(&it->second)) return *value;
  return 0;
}
bool Boolean(const Map& data, const char* key) {
  const auto it = data.find(Value(key));
  return it != data.end() && std::get_if<bool>(&it->second) &&
      std::get<bool>(it->second);
}
}  // namespace

WindowsIntegrations::WindowsIntegrations(flutter::BinaryMessenger* messenger,
                                         HWND parent, HWND view)
    : parent_(parent), view_(view) {
  input_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "pilipili/windows_input", &flutter::StandardMethodCodec::GetInstance());
  input_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "showKeyboard" || call.method_name() == "hideKeyboard") {
      result->Success(Value(Keyboard(call.method_name() == "showKeyboard")));
    } else {
      result->NotImplemented();
    }
  });
  media_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "pilipili/smtc", &flutter::StandardMethodCodec::GetInstance());
  media_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      if (call.method_name() == "setEnabled") {
        const auto enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
        if (!enabled) { result->Error("bad-arguments", "Expected enabled flag"); return; }
        SetEnabled(*enabled);
        result->Success();
      } else if (call.method_name() == "update") {
        const auto data = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        if (!data) { result->Error("bad-arguments", "Expected media metadata"); return; }
        UpdateMedia(*data);
        result->Success();
      } else {
        result->NotImplemented();
      }
    } catch (const winrt::hresult_error&) {
      result->Error("windows-media-unavailable", "Windows media integration is unavailable");
    }
  });
}

WindowsIntegrations::~WindowsIntegrations() {
  input_channel_->SetMethodCallHandler(nullptr);
  media_channel_->SetMethodCallHandler(nullptr);
  if (controls_) {
    try {
      controls_.ButtonPressed(button_token_);
      controls_.PlaybackPositionChangeRequested(seek_token_);
      controls_.IsEnabled(false);
      controls_.DisplayUpdater().ClearAll();
    } catch (const winrt::hresult_error&) {}
  }
}

bool WindowsIntegrations::Keyboard(bool show) {
  // Do not reopen the keyboard or hide another app's keyboard after a focus change.
  if (GetAncestor(GetForegroundWindow(), GA_ROOT) != GetAncestor(parent_, GA_ROOT)) return false;
  try {
    if (!input_pane_) {
      const auto interop = winrt::get_activation_factory<
          winrt::Windows::UI::ViewManagement::InputPane, IInputPaneInterop>();
      winrt::check_hresult(interop->GetForWindow(
          view_, winrt::guid_of<winrt::Windows::UI::ViewManagement::InputPane>(),
          winrt::put_abi(input_pane_)));
    }
    if (show) {
      return input_pane_.TryShow();
    }
    return input_pane_.TryHide();
  } catch (const winrt::hresult_error&) {
    return false;
  }
}

void WindowsIntegrations::EnsureMediaControls() {
  if (controls_) return;
  const auto interop = winrt::get_activation_factory<
      SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
  winrt::check_hresult(interop->GetForWindow(
      parent_, winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls_)));
  const HWND parent = parent_;
  button_token_ = controls_.ButtonPressed([parent](const auto&, const auto& args) {
    PostMessage(parent, kMediaButton, static_cast<WPARAM>(args.Button()), 0);
  });
  seek_token_ = controls_.PlaybackPositionChangeRequested([parent](const auto&, const auto& args) {
    const auto position = std::chrono::duration_cast<std::chrono::milliseconds>(
        args.RequestedPlaybackPosition()).count();
    PostMessage(parent, kMediaSeek, static_cast<WPARAM>(position), 0);
  });
  controls_.IsPlayEnabled(true);
  controls_.IsPauseEnabled(true);
  controls_.IsStopEnabled(false);
}

void WindowsIntegrations::SetEnabled(bool enabled) {
  if (enabled) EnsureMediaControls();
  if (!controls_) return;
  controls_.IsEnabled(enabled);
  if (!enabled) {
    controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
    controls_.DisplayUpdater().ClearAll();
    controls_.DisplayUpdater().Update();
    metadata_set_ = false;
    title_.clear();
    artist_.clear();
    artwork_.clear();
    artwork_bytes_.clear();
  }
}

void WindowsIntegrations::UpdateMedia(const Map& data) {
  EnsureMediaControls();
  const auto title = String(data, "title");
  const auto artist = String(data, "artist");
  const auto artwork = String(data, "artwork");
  const auto artwork_it = data.find(Value("artworkBytes"));
  const auto bytes = artwork_it == data.end() ? nullptr :
      std::get_if<std::vector<uint8_t>>(&artwork_it->second);
  const std::vector<uint8_t> empty;
  const auto& artwork_bytes = bytes ? *bytes : empty;
  if (!metadata_set_ || title != title_ || artist != artist_ || artwork != artwork_ ||
      artwork_bytes != artwork_bytes_) {
    const auto updater = controls_.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
    updater.MusicProperties().Title(winrt::to_hstring(title));
    updater.MusicProperties().Artist(winrt::to_hstring(artist));
    updater.Thumbnail(nullptr);
    if (!artwork_bytes.empty()) {
      try {
        winrt::com_ptr<IStream> memory;
        memory.attach(SHCreateMemStream(artwork_bytes.data(),
            static_cast<UINT>(artwork_bytes.size())));
        winrt::check_pointer(memory.get());
        using namespace winrt::Windows::Storage::Streams;
        IRandomAccessStream stream{nullptr};
        winrt::check_hresult(CreateRandomAccessStreamOverStream(memory.get(), BSOS_DEFAULT,
            winrt::guid_of<IRandomAccessStream>(), winrt::put_abi(stream)));
        updater.Thumbnail(RandomAccessStreamReference::CreateFromStream(stream));
      } catch (const winrt::hresult_error&) {
        // Artwork availability must never prevent titles or media controls.
      }
    }
    updater.Update();
    metadata_set_ = true;
    title_ = title;
    artist_ = artist;
    artwork_ = artwork;
    artwork_bytes_ = artwork_bytes;
  }
  controls_.IsNextEnabled(Boolean(data, "canSkip"));
  controls_.IsPreviousEnabled(Boolean(data, "canSkip"));
  controls_.PlaybackStatus(Boolean(data, "playing") ?
      MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
  const auto duration = std::max<int64_t>(0, Integer(data, "durationMs"));
  const auto position = std::clamp<int64_t>(Integer(data, "positionMs"), 0, duration);
  SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(std::chrono::milliseconds(0));
  timeline.EndTime(std::chrono::milliseconds(duration));
  timeline.MinSeekTime(std::chrono::milliseconds(0));
  timeline.MaxSeekTime(std::chrono::milliseconds(duration));
  timeline.Position(std::chrono::milliseconds(position));
  controls_.UpdateTimelineProperties(timeline);
  controls_.IsEnabled(true);
}

bool WindowsIntegrations::HandleMessage(UINT message, WPARAM wparam, LPARAM) {
  if (message == kMediaButton) {
    if (!controls_ || !controls_.IsEnabled()) return true;
    const char* command = nullptr;
    switch (static_cast<SystemMediaTransportControlsButton>(wparam)) {
      case SystemMediaTransportControlsButton::Play: command = "play"; break;
      case SystemMediaTransportControlsButton::Pause: command = "pause"; break;
      case SystemMediaTransportControlsButton::Next: command = "next"; break;
      case SystemMediaTransportControlsButton::Previous: command = "previous"; break;
      default: break;
    }
    if (command) media_channel_->InvokeMethod(command, nullptr);
    return true;
  }
  if (message == kMediaSeek) {
    if (controls_ && controls_.IsEnabled())
      media_channel_->InvokeMethod("seek", std::make_unique<Value>(static_cast<int64_t>(wparam)));
    return true;
  }
  return false;
}
