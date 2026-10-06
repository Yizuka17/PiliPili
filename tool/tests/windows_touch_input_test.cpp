#include <tchar.h>
#include <tpcshrd.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <iostream>
#include <algorithm>
#include <vector>

#include "windows_touch_input.h"
#include "windows_brightness.h"

namespace {
int pointer_down = 0;
int mouse_down = 0;
int mouse_up = 0;
int mouse_leave = 0;
int activate = 0;

LRESULT CALLBACK TestWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_POINTERDOWN) ++pointer_down;
  if (message == WM_RBUTTONDOWN) ++mouse_down;
  if (message == WM_RBUTTONUP) ++mouse_up;
  if (message == WM_MOUSELEAVE) ++mouse_leave;
  if (message == WM_ACTIVATE) {
    ++activate;
    // These are manually sent to hidden test windows. Avoid DefWindowProc's
    // focus/activation side effects on the user's foreground application.
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

class TestMessenger : public flutter::BinaryMessenger {
 public:
  flutter::BinaryMessageHandler handler;
  mutable int raw_messages = 0;
  mutable std::vector<std::string> messages;
  mutable std::vector<flutter::EncodableMap> records;
  void Send(const std::string&, const uint8_t* message, size_t size,
            flutter::BinaryReply = nullptr) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(message, size);
    if (call && call->method_name() == "nativeInput") {
      ++raw_messages;
      const auto& data = std::get<flutter::EncodableMap>(*call->arguments());
      records.push_back(data);
      messages.push_back(std::get<std::string>(data.at(flutter::EncodableValue("message"))));
    }
  }
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler value) override {
    handler = std::move(value);
  }
};

bool CheckWindow(HWND window) {
  GESTURECONFIG config{GID_PAN, 0, 0};
  UINT count = 1;
  const auto property = reinterpret_cast<ULONG_PTR>(GetProp(window, MICROSOFT_TABLETPENSERVICE_PROPERTY));
  const auto query = SendMessage(window, WM_TABLET_QUERYSYSTEMGESTURESTATUS, 0, 0);
  const auto configured = GetGestureConfig(window, 0, 0, &count, &config, sizeof(config));
  std::cout << "property=" << property << " query=" << query << " configured=" << configured
            << " want=" << config.dwWant << " block=" << config.dwBlock << " error=" << GetLastError() << '\n';
  return (property &
          TABLET_DISABLE_PRESSANDHOLD) != 0 &&
         query == TABLET_DISABLE_PRESSANDHOLD && configured &&
         config.dwWant == 0 && (config.dwBlock & GC_PAN) != 0;
}

bool CheckHoverPolicy() {
  const INPUT_MESSAGE_SOURCE system{IMDT_UNAVAILABLE, IMO_SYSTEM};
  const INPUT_MESSAGE_SOURCE mouse{IMDT_MOUSE, IMO_HARDWARE};
  const INPUT_MESSAGE_SOURCE touch{IMDT_TOUCH, IMO_HARDWARE};
  const INPUT_MESSAGE_SOURCE pen{IMDT_PEN, IMO_HARDWARE};
  const INPUT_MESSAGE_SOURCE injected{IMDT_MOUSE, IMO_INJECTED};
  const INPUT_MESSAGE_SOURCE pad{IMDT_TOUCHPAD, IMO_HARDWARE};
  WindowsTouchHoverPolicy policy;
  auto send = [&](UINT message, WPARAM buttons, POINTER_INPUT_TYPE type,
                  INPUT_MESSAGE_SOURCE source, bool known = true,
                  LPARAM extra = 0) {
    return policy.Handle(message, buttons, type, known, source, extra);
  };
  // A layout/system cursor refresh is legitimate before touch input.
  if (send(WM_MOUSEMOVE, 0, PT_POINTER, system).suppress_move) return false;
  if (!send(WM_POINTERDOWN, 1, PT_TOUCH, touch).clear_hover) return false;
  // Touch release, leave and compatibility messages must not re-enable hover.
  send(WM_POINTERUP, 1, PT_TOUCH, touch);
  send(WM_MOUSEMOVE, 0, PT_POINTER, touch, true, 0xFF515780);
  send(WM_LBUTTONUP, 0, PT_POINTER, touch, true, 0xFF515780);
  if (!policy.touch_mode() ||
      !send(WM_MOUSEMOVE, 0, PT_POINTER, system).suppress_move) return false;
  // Pen hover must pass through, and real mouse/trackpad use restores hover.
  if (send(WM_MOUSEMOVE, 0, PT_PEN, pen, true, 0xFF515700).suppress_move) return false;
  if (send(WM_MOUSEMOVE, 0, PT_MOUSE, mouse).suppress_move || policy.touch_mode()) return false;
  if (send(WM_MOUSEMOVE, 0, PT_POINTER, system).suppress_move) return false;
  send(WM_POINTERDOWN, 1, PT_TOUCH, touch);
  if (send(WM_MOUSEMOVE, 0, PT_MOUSE, injected).suppress_move || policy.touch_mode()) return false;
  send(WM_POINTERDOWN, 1, PT_TOUCH, touch);
  if (send(WM_MOUSEMOVE, 0, PT_TOUCHPAD, pad).suppress_move || policy.touch_mode()) return false;
  // No timers or blanket filters: unknown legacy mouse input can recover.
  send(WM_POINTERDOWN, 1, PT_TOUCH, touch);
  if (send(WM_MOUSEMOVE, 0, PT_POINTER, {}, false).suppress_move || policy.touch_mode()) return false;
  // A real mouse drag overlapping a touch must never be removed mid-drag.
  send(WM_LBUTTONDOWN, MK_LBUTTON, PT_MOUSE, mouse);
  if (send(WM_POINTERDOWN, 1, PT_TOUCH, touch).clear_hover) return false;
  if (send(WM_MOUSEMOVE, MK_LBUTTON, PT_POINTER, system).suppress_move) return false;
  send(WM_LBUTTONUP, 0, PT_MOUSE, mouse);
  if (!send(WM_POINTERDOWN, 1, PT_TOUCH, touch).clear_hover) return false;
  // Buttons/wheel/leave are never swallowed even while touch is active.
  if (send(WM_RBUTTONDOWN, MK_RBUTTON, PT_MOUSE, mouse).suppress_move || policy.touch_mode()) return false;
  send(WM_RBUTTONUP, 0, PT_MOUSE, mouse);
  send(WM_POINTERDOWN, 1, PT_TOUCH, touch);
  if (send(WM_MOUSEWHEEL, 0, PT_MOUSE, mouse).suppress_move || policy.touch_mode()) return false;
  send(WM_POINTERDOWN, 1, PT_TOUCH, touch);
  if (send(WM_MOUSELEAVE, 0, PT_POINTER, system).suppress_move) return false;
  // A failed pointer-type query or pen contact must not clear mouse hover.
  if (send(WM_POINTERDOWN, 1, PT_POINTER, {}).clear_hover ||
      send(WM_POINTERDOWN, 1, PT_PEN, pen).clear_hover) return false;
  std::cout << "Hover policy passed: touch release, system refresh, mouse/pen/trackpad, unknown source, overlapping drag\n";
  return true;
}

bool CheckReentryPolicy() {
  const INPUT_MESSAGE_SOURCE system{IMDT_UNAVAILABLE, IMO_SYSTEM};
  const INPUT_MESSAGE_SOURCE system_mouse{IMDT_MOUSE, IMO_SYSTEM};
  const INPUT_MESSAGE_SOURCE mouse{IMDT_MOUSE, IMO_HARDWARE};
  const INPUT_MESSAGE_SOURCE touch{IMDT_TOUCH, IMO_HARDWARE};
  const INPUT_MESSAGE_SOURCE pen{IMDT_PEN, IMO_HARDWARE};
  const POINT before{300, 400};
  const POINT external_mouse{800, 600};
  const POINT moved{801, 600};
  WindowsTouchHoverPolicy policy;
  // A touch inside the app needs the same protection as window reentry.
  policy.Handle(WM_POINTERDOWN, 1, PT_TOUCH, true, touch, 0, &before);
  for (const auto source : {mouse, INPUT_MESSAGE_SOURCE{}}) {
    if (!policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, source, 0,
                       &before).suppress_move || !policy.touch_mode()) return false;
  }
  if (policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, mouse, 0,
                    &moved).suppress_move || policy.touch_mode()) return false;
  policy.Handle(WM_POINTERDOWN, 1, PT_TOUCH, true, touch, 0);
  policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, mouse, 0, &before);
  if (policy.touch_mode()) return false;
  // Reproduce a mouse used in another window, followed by a taskbar/gesture
  // return. No WM_POINTERDOWN from that shell gesture reaches this HWND.
  if (!policy.Reactivate(&external_mouse, true).clear_hover ||
      !policy.touch_mode() || !policy.awaiting_mouse_activity()) return false;
  for (const auto source : {system, system_mouse, mouse}) {
    if (!policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, source, 0,
                       &external_mouse).suppress_move) return false;
  }
  // Returning while the cursor is still visible also needs a fresh action;
  // don't rely solely on CURSOR_SUPPRESSED to distinguish an old cursor.
  policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, mouse, 0, &moved);
  if (policy.awaiting_mouse_activity() || policy.touch_mode()) return false;
  if (policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, system, 0, &moved).suppress_move) return false;
  if (!policy.Reactivate(&external_mouse, false).clear_hover) return false;
  if (!policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, {}, 0,
                     &external_mouse).suppress_move) return false;
  // A window/layout move cannot count as mouse movement. The adapter compares
  // screen cursor coordinates rather than old client-relative WM_MOUSEMOVE.
  if (!policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, mouse, 0,
                     &external_mouse).suppress_move) return false;
  if (policy.Handle(WM_POINTERUPDATE, 0, PT_PEN, true, pen, 0).suppress_move) return false;
  if (policy.Handle(WM_MOUSEMOVE, 0, PT_PEN, true, pen, 0xFF515700,
                    &external_mouse).suppress_move) return false;
  // Actual mouse clicks restore use without requiring movement first.
  if (policy.Handle(WM_RBUTTONDOWN, MK_RBUTTON, PT_MOUSE, true, mouse, 0,
                    &external_mouse).suppress_move || policy.awaiting_mouse_activity()) return false;
  if (policy.Reactivate(&external_mouse, false).clear_hover) return false;
  policy.Handle(WM_RBUTTONUP, 0, PT_MOUSE, true, mouse, 0);
  policy.Reactivate(nullptr, false);
  // If cursor querying fails, don't permanently block known mouse hardware.
  if (policy.Handle(WM_MOUSEMOVE, 0, PT_MOUSE, true, mouse, 0).suppress_move ||
      policy.awaiting_mouse_activity()) return false;
  std::cout << "Reentry policy passed: external mouse then touch/keyboard return, stationary refresh, fresh movement/click, pen, query failure\n";
  return true;
}
}  // namespace

int main() {
  if (!CheckHoverPolicy()) return 7;
  if (!CheckReentryPolicy()) return 9;
  WNDCLASS wc{};
  wc.lpfnWndProc = TestWindowProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"PiliTouchPolicyTest";
  if (!RegisterClass(&wc)) return 1;
  HWND parent = CreateWindow(wc.lpszClassName, L"touch-test", WS_OVERLAPPED,
                            0, 0, 200, 200, nullptr, nullptr, wc.hInstance, nullptr);
  HWND view = CreateWindow(wc.lpszClassName, L"view", WS_CHILD,
                          0, 0, 100, 100, parent, nullptr, wc.hInstance, nullptr);
  if (!parent || !view) return 2;
  SetProp(parent, MICROSOFT_TABLETPENSERVICE_PROPERTY,
          reinterpret_cast<HANDLE>(TABLET_DISABLE_PENTAPFEEDBACK));
  TestMessenger messenger;
  {
    WindowsTouchInput input(&messenger, parent, view);
    if (!CheckWindow(parent) || !CheckWindow(view)) return 3;
    const auto start = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<flutter::EncodableValue>("startDiagnostics", nullptr));
    bool replied = false;
    messenger.handler(start->data(), start->size(),
                      [&replied](const uint8_t* data, size_t size) {
                        replied = data != nullptr && size > 0;
                      });
    if (!replied) return 4;
    const auto cursor_call = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<flutter::EncodableValue>("getCursorSnapshot", nullptr));
    bool cursor_valid = false;
    messenger.handler(cursor_call->data(), cursor_call->size(),
      [&cursor_valid](const uint8_t* data, size_t size) {
        flutter::MethodResultFunctions<flutter::EncodableValue> result(
              [&cursor_valid](const flutter::EncodableValue* value) {
                using Value = flutter::EncodableValue;
                const auto& snapshot = std::get<flutter::EncodableMap>(*value);
                cursor_valid = std::get<bool>(snapshot.at(Value("known"))) &&
                    snapshot.count(Value("screenX")) && snapshot.count(Value("screenY")) &&
                    snapshot.count(Value("showing")) && snapshot.count(Value("suppressed"));
              }, nullptr, nullptr);
        flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(data, size, &result);
      });
    if (!cursor_valid) return 8;
    // Ordinary right-clicks and raw touch must still reach the original WndProc.
    SendMessage(view, WM_RBUTTONDOWN, MK_RBUTTON, MAKELPARAM(10, 10));
    SendMessage(view, WM_RBUTTONUP, 0, MAKELPARAM(10, 10));
    SendMessage(view, WM_POINTERDOWN, 1, MAKELPARAM(20, 20));
    if (mouse_down != 1 || mouse_up != 1 || pointer_down != 1) return 5;
    for (const auto* name : {"WM_RBUTTONDOWN", "WM_RBUTTONUP", "WM_POINTERDOWN"}) {
      if (std::find(messenger.messages.begin(), messenger.messages.end(), name) ==
          messenger.messages.end()) return 5;
    }
    if (!messenger.records.front().count(flutter::EncodableValue("cursor"))) return 8;
    const auto before_activate = activate;
    const auto before_leave = mouse_leave;
    SendMessage(parent, WM_ACTIVATE, WA_INACTIVE, 0);
    if (mouse_leave != before_leave) {
      std::cerr << "Unexpected leave on deactivation: " << before_leave << " -> " << mouse_leave << '\n';
      return 10;
    }
    SendMessage(parent, WM_ACTIVATE, WA_ACTIVE, 0);
    if (activate != before_activate + 2 || mouse_leave != before_leave + 1) {
      std::cerr << "Activation/leave counts: " << before_activate << " -> " << activate
                << ", " << before_leave << " -> " << mouse_leave << '\n';
      return 10;
    }
    using Value = flutter::EncodableValue;
    const auto activation = std::find_if(messenger.records.rbegin(), messenger.records.rend(),
      [](const auto& record) {
        return std::get<std::string>(record.at(Value("message"))) == "WM_ACTIVATE" &&
            std::get<int64_t>(record.at(Value("activation"))) == WA_ACTIVE;
      });
    if (activation == messenger.records.rend() ||
        !std::get<bool>(activation->at(Value("awaitingMouseActivity")))) {
      std::cerr << "Missing activation baseline record\n";
      return 10;
    }
  }
  if (messenger.handler || GetProp(view, MICROSOFT_TABLETPENSERVICE_PROPERTY) != nullptr ||
      GetProp(parent, MICROSOFT_TABLETPENSERVICE_PROPERTY) !=
          reinterpret_cast<HANDLE>(TABLET_DISABLE_PENTAPFEEDBACK)) return 6;
  {
    // Read only: validate the real WMI path or a clean unsupported response.
    // Do not alter the user's panel brightness during build checks.
    WindowsBrightness brightness(&messenger, view);
    const auto request = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<flutter::EncodableValue>("getBrightness", nullptr));
    std::vector<RECT> displays;
    EnumDisplayMonitors(nullptr, nullptr,
      [](HMONITOR, HDC, LPRECT rect, LPARAM context) -> BOOL {
        reinterpret_cast<std::vector<RECT>*>(context)->push_back(*rect);
        return TRUE;
      }, reinterpret_cast<LPARAM>(&displays));
    if (displays.empty()) displays.push_back(RECT{0, 0, 200, 200});
    for (const auto& display : displays) {
      SetWindowPos(parent, nullptr, display.left + 10, display.top + 10, 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    bool valid = false;
    double current_brightness = -1;
    messenger.handler(request->data(), request->size(),
      [&valid, &current_brightness](const uint8_t* data, size_t size) {
        flutter::MethodResultFunctions<flutter::EncodableValue> result(
          [&valid, &current_brightness](const flutter::EncodableValue* value) {
            const auto* brightness = value ? std::get_if<double>(value) : nullptr;
            valid = brightness && *brightness >= 0 && *brightness <= 1;
            if (valid) {
              current_brightness = *brightness;
              std::cout << "WMI brightness read: " << *brightness << '\n';
            }
          },
          [&valid](const std::string& code, const std::string&, const flutter::EncodableValue*) {
            valid = code == "unavailable";
            if (valid) std::cout << "WMI brightness unavailable; DDC/volume fallback applies\n";
          }, nullptr);
        flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(data, size, &result);
      });
    if (!valid) return 11;
    if (current_brightness >= 0) {
      // Exercise the setter using the current level, leaving brightness unchanged.
      const auto unchanged = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
          flutter::MethodCall<flutter::EncodableValue>("setBrightness",
              std::make_unique<flutter::EncodableValue>(current_brightness)));
      bool write_valid = false;
      messenger.handler(unchanged->data(), unchanged->size(),
        [&write_valid](const uint8_t* data, size_t size) {
          flutter::MethodResultFunctions<flutter::EncodableValue> result(
            [&write_valid](const flutter::EncodableValue*) {
              write_valid = true;
              std::cout << "WMI brightness setter passed at unchanged level\n";
            },
            [&write_valid](const std::string& code, const std::string&, const flutter::EncodableValue*) {
              write_valid = code == "unavailable";
              if (write_valid) std::cout << "WMI setter unavailable; volume fallback applies\n";
            }, nullptr);
          flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(data, size, &result);
        });
      if (!write_valid) return 12;
    }
    }
  }
  DestroyWindow(parent);
  UnregisterClass(wc.lpszClassName, wc.hInstance);
  std::cout << "Native touch policy passed: parent/view configuration, raw touch and mouse forwarding, diagnostics, cleanup\n";
  return 0;
}
