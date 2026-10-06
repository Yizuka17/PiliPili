#include "windows_touch_input.h"

#include <tchar.h>
#include <tpcshrd.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>

namespace {
constexpr DWORD kTabletFlags = TABLET_DISABLE_PRESSANDHOLD;
constexpr UINT_PTR kSubclassId = 1;
constexpr WPARAM kMouseButtons = MK_LBUTTON | MK_RBUTTON | MK_MBUTTON |
                                 MK_XBUTTON1 | MK_XBUTTON2;
constexpr LPARAM kTouchOrPenSignature = 0xFF515700;
constexpr LPARAM kSignatureMask = 0xFFFFFF00;

const char* InputMessageName(UINT message) {
  switch (message) {
    case WM_POINTERDOWN: return "WM_POINTERDOWN";
    case WM_POINTERUPDATE: return "WM_POINTERUPDATE";
    case WM_POINTERUP: return "WM_POINTERUP";
    case WM_POINTERLEAVE: return "WM_POINTERLEAVE";
    case WM_MOUSEMOVE: return "WM_MOUSEMOVE";
    case WM_MOUSELEAVE: return "WM_MOUSELEAVE";
    case WM_LBUTTONDOWN: return "WM_LBUTTONDOWN";
    case WM_LBUTTONUP: return "WM_LBUTTONUP";
    case WM_RBUTTONDOWN: return "WM_RBUTTONDOWN";
    case WM_RBUTTONUP: return "WM_RBUTTONUP";
    case WM_MBUTTONDOWN: return "WM_MBUTTONDOWN";
    case WM_MBUTTONUP: return "WM_MBUTTONUP";
    case WM_XBUTTONDOWN: return "WM_XBUTTONDOWN";
    case WM_XBUTTONUP: return "WM_XBUTTONUP";
    case WM_MOUSEWHEEL: return "WM_MOUSEWHEEL";
    case WM_MOUSEHWHEEL: return "WM_MOUSEHWHEEL";
    case WM_CONTEXTMENU: return "WM_CONTEXTMENU";
    case WM_ACTIVATE: return "WM_ACTIVATE";
    case WM_ACTIVATEAPP: return "WM_ACTIVATEAPP";
    case WM_MOUSEACTIVATE: return "WM_MOUSEACTIVATE";
    case WM_SETFOCUS: return "WM_SETFOCUS";
    case WM_KILLFOCUS: return "WM_KILLFOCUS";
    case WM_TABLET_QUERYSYSTEMGESTURESTATUS:
      return "WM_TABLET_QUERYSYSTEMGESTURESTATUS";
    default: return nullptr;
  }
}
}  // namespace

WindowsTouchHoverPolicy::Decision WindowsTouchHoverPolicy::Handle(
    UINT message, WPARAM wparam, POINTER_INPUT_TYPE pointer_type,
    bool source_known, INPUT_MESSAGE_SOURCE source, LPARAM extra_info,
    const POINT* screen_position) {
  Decision decision;
  if (message == WM_POINTERDOWN && pointer_type == PT_TOUCH && mouse_buttons_ == 0) {
    touch_mode_ = true;
    // The same stationary-mouse guard also applies to in-app touch. Windows
    // can relabel a stale cursor refresh as mouse hardware or unknown input.
    awaiting_mouse_activity_ = true;
    reentry_position_known_ = screen_position != nullptr;
    if (screen_position) reentry_position_ = *screen_position;
    decision.clear_hover = true;
  }
  const bool promoted = (extra_info & kSignatureMask) == kTouchOrPenSignature;
  const bool mouse_message = message == WM_MOUSEMOVE ||
      (message >= WM_LBUTTONDOWN && message <= WM_MBUTTONDBLCLK) ||
      message == WM_XBUTTONDOWN || message == WM_XBUTTONUP ||
      message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL;
  // Never infer a real mouse from Windows' touch/pen promotion. Unknown-source
  // legacy mouse messages still pass through and can restore normal mouse use.
  const bool real_mouse = mouse_message && !promoted &&
      (!source_known || source.originId != IMO_SYSTEM ||
       message != WM_MOUSEMOVE || (wparam & kMouseButtons) != 0) &&
      (!source_known || source.deviceType == IMDT_UNAVAILABLE ||
       source.deviceType == IMDT_MOUSE || source.deviceType == IMDT_TOUCHPAD);
  const bool stationary_reentry = awaiting_mouse_activity_ && real_mouse &&
      message == WM_MOUSEMOVE && (wparam & kMouseButtons) == 0 &&
      reentry_position_known_ && screen_position &&
      screen_position->x == reentry_position_.x &&
      screen_position->y == reentry_position_.y;
  if (stationary_reentry) {
    // Windows can refresh the old cursor when a window is activated. A hardware
    // source label alone does not prove the mouse actually moved after return.
    decision.suppress_move = true;
    return decision;
  }
  if (real_mouse) {
    touch_mode_ = false;
    awaiting_mouse_activity_ = false;
    mouse_buttons_ = wparam & kMouseButtons;
  }
  const bool system_refresh = source_known && source.originId == IMO_SYSTEM &&
      (source.deviceType == IMDT_UNAVAILABLE ||
       (awaiting_mouse_activity_ &&
        (source.deviceType == IMDT_MOUSE || source.deviceType == IMDT_TOUCHPAD)));
  decision.suppress_move = (touch_mode_ || awaiting_mouse_activity_) && mouse_buttons_ == 0 &&
      message == WM_MOUSEMOVE && (wparam & kMouseButtons) == 0 &&
      system_refresh && !promoted;
  return decision;
}

WindowsTouchHoverPolicy::Decision WindowsTouchHoverPolicy::Reactivate(
    const POINT* cursor_position, bool cursor_suppressed) {
  Decision decision;
  // Do not remove a pressed mouse device when a window is activated mid-drag.
  if (mouse_buttons_ != 0) return decision;
  awaiting_mouse_activity_ = true;
  reentry_position_known_ = cursor_position != nullptr;
  if (cursor_position) reentry_position_ = *cursor_position;
  if (cursor_suppressed) touch_mode_ = true;
  decision.clear_hover = true;
  return decision;
}

WindowsTouchInput::WindowsTouchInput(flutter::BinaryMessenger* messenger,
                                   HWND parent, HWND view)
    : parent_{parent, nullptr, false, false, "parent"},
      view_{view, nullptr, false, false, "view"} {
  ConfigureWindow(parent_);
  ConfigureWindow(view_);
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pilipili/windows_touch", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "startDiagnostics") {
          logging_ = true;
          if (!cursor_timer_) {
            cursor_timer_ = SetTimer(parent_.handle, reinterpret_cast<UINT_PTR>(this), 100, nullptr);
          }
          configuration_[flutter::EncodableValue("cursorSampling")] =
              flutter::EncodableValue(cursor_timer_ != 0);
          configuration_[flutter::EncodableValue("touchHoverPolicy")] =
              flutter::EncodableValue("clear-on-touch-and-activation-await-fresh-mouse");
          result->Success(flutter::EncodableValue(configuration_));
          RecordCursor();
        } else if (call.method_name() == "getCursorSnapshot") {
          result->Success(flutter::EncodableValue(CursorSnapshot()));
        } else {
          result->NotImplemented();
        }
      });
  // Opening the app by touch does not deliver the taskbar's WM_POINTERDOWN to
  // this window. Establish the same baseline used when returning to it.
  ReactivateHover();
}

WindowsTouchInput::~WindowsTouchInput() {
  logging_ = false;
  if (cursor_timer_) KillTimer(parent_.handle, cursor_timer_);
  channel_->SetMethodCallHandler(nullptr);
  RestoreWindow(view_);
  RestoreWindow(parent_);
}

void WindowsTouchInput::ConfigureWindow(WindowState& window) {
  using Value = flutter::EncodableValue;
  window.previous_tablet_property = GetProp(window.handle, MICROSOFT_TABLETPENSERVICE_PROPERTY);
  auto flags = reinterpret_cast<ULONG_PTR>(window.previous_tablet_property) | kTabletFlags;
  window.property_set = SetProp(window.handle, MICROSOFT_TABLETPENSERVICE_PROPERTY,
                               reinterpret_cast<HANDLE>(flags)) != FALSE;
  const auto property_error = window.property_set ? 0 : GetLastError();
  // SetGestureConfig is the documented Windows 7+ counterpart to the tablet
  // property/query. Raw WM_POINTER touch still reaches Flutter unchanged.
  GESTURECONFIG gestures{0, 0, GC_ALLGESTURES};
  const bool gesture_set = SetGestureConfig(window.handle, 0, 1, &gestures,
                                            sizeof(gestures)) != FALSE;
  const auto gesture_error = gesture_set ? 0 : GetLastError();
  window.subclass_set = SetWindowSubclass(window.handle, SubclassProc, kSubclassId,
                                         reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  configuration_[Value(window.role)] = Value(flutter::EncodableMap{
      {Value("tabletFlags"), Value(static_cast<int64_t>(flags))},
      {Value("propertySet"), Value(window.property_set)},
      {Value("propertyError"), Value(static_cast<int64_t>(property_error))},
      {Value("gesturesBlocked"), Value(gesture_set)},
      {Value("gestureError"), Value(static_cast<int64_t>(gesture_error))},
      {Value("subclassSet"), Value(window.subclass_set)},
  });
}

void WindowsTouchInput::RestoreWindow(const WindowState& window) {
  if (!IsWindow(window.handle)) return;
  if (window.subclass_set) RemoveWindowSubclass(window.handle, SubclassProc, kSubclassId);
  if (window.property_set) {
    if (window.previous_tablet_property) {
      SetProp(window.handle, MICROSOFT_TABLETPENSERVICE_PROPERTY, window.previous_tablet_property);
    } else {
      RemoveProp(window.handle, MICROSOFT_TABLETPENSERVICE_PROPERTY);
    }
  }
}

LRESULT CALLBACK WindowsTouchInput::SubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) {
  auto* input = reinterpret_cast<WindowsTouchInput*>(reference_data);
  if (message == WM_TIMER && window == input->parent_.handle &&
      input->cursor_timer_ && wparam == input->cursor_timer_) {
    input->RecordCursor();
    return 0;
  }
  INPUT_MESSAGE_SOURCE source{};
  const bool source_known = GetCurrentInputMessageSource(&source) != FALSE;
  POINTER_INPUT_TYPE pointer_type = PT_POINTER;
  if (message == WM_POINTERDOWN) {
    GetPointerType(GET_POINTERID_WPARAM(wparam), &pointer_type);
  }
  const bool reactivated = window == input->parent_.handle &&
      message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE;
  const bool clear_reentry = reactivated && input->ReactivateHover();
  POINT screen_position{};
  const bool position_known = (message == WM_MOUSEMOVE || message == WM_POINTERDOWN) &&
      GetCursorPos(&screen_position) != FALSE;
  const auto decision = input->hover_policy_.Handle(
      message, wparam, pointer_type, source_known, source, GetMessageExtraInfo(),
      position_known ? &screen_position : nullptr);
  input->RecordMessage(window, message, wparam, lparam, decision.suppress_move,
                       clear_reentry ? "resetReentryHover" : nullptr);
  if (decision.clear_hover) input->ClearMouseHover("clearTouchHover");
  if (decision.suppress_move) return 0;
  if (message == WM_TABLET_QUERYSYSTEMGESTURESTATUS) return kTabletFlags;
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, SubclassProc, subclass_id);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

void WindowsTouchInput::RecordMessage(HWND window, UINT message,
                                      WPARAM wparam, LPARAM lparam,
                                      bool suppressed, const char* action) {
  const auto* name = InputMessageName(message);
  if (!logging_ || !name) return;
  const auto now = GetTickCount64();
  if (!suppressed && (message == WM_MOUSEMOVE || message == WM_POINTERUPDATE)) {
    if (now - last_move_ms_ < 16) return;
    last_move_ms_ = now;
  }
  using Value = flutter::EncodableValue;
  INPUT_MESSAGE_SOURCE source{};
  const bool source_known = GetCurrentInputMessageSource(&source) != FALSE;
  flutter::EncodableMap data{
      {Value("message"), Value(name)},
      {Value("window"), Value(window == view_.handle ? "view" : "parent")},
      {Value("tickMs"), Value(static_cast<int64_t>(now))},
      {Value("messageTimeMs"), Value(static_cast<int64_t>(GetMessageTime()))},
      {Value("wparam"), Value(static_cast<int64_t>(wparam))},
      {Value("extraInfo"), Value(static_cast<int64_t>(GetMessageExtraInfo()))},
      {Value("sourceKnown"), Value(source_known)},
      {Value("sourceDevice"), Value(static_cast<int64_t>(source.deviceType))},
      {Value("sourceOrigin"), Value(static_cast<int64_t>(source.originId))},
      {Value("captureIsView"), Value(GetCapture() == view_.handle)},
      {Value("suppressed"), Value(suppressed)},
      {Value("touchMode"), Value(hover_policy_.touch_mode())},
      {Value("awaitingMouseActivity"), Value(hover_policy_.awaiting_mouse_activity())},
      {Value("cursor"), Value(CursorSnapshot())},
  };
  if (action) data[Value("action")] = Value(action);
  if (message == WM_ACTIVATE) {
    data[Value("activation")] = Value(static_cast<int64_t>(LOWORD(wparam)));
    data[Value("minimized")] = Value(HIWORD(wparam) != 0);
  }
  if (message == WM_ACTIVATEAPP) data[Value("active")] = Value(wparam != 0);
  if (message == WM_POINTERDOWN || message == WM_POINTERUPDATE ||
      message == WM_POINTERUP || message == WM_POINTERLEAVE) {
    const auto id = GET_POINTERID_WPARAM(wparam);
    POINTER_INPUT_TYPE type = PT_POINTER;
    POINTER_INFO info{};
    data[Value("pointerId")] = Value(static_cast<int64_t>(id));
    if (GetPointerType(id, &type)) {
      data[Value("pointerType")] = Value(static_cast<int64_t>(type));
    }
    if (GetPointerInfo(id, &info)) {
      data[Value("pointerFlags")] = Value(static_cast<int64_t>(info.pointerFlags));
    }
  }
  if (message != WM_MOUSELEAVE && message != WM_TABLET_QUERYSYSTEMGESTURESTATUS &&
      message != WM_ACTIVATE && message != WM_ACTIVATEAPP &&
      message != WM_MOUSEACTIVATE && message != WM_SETFOCUS && message != WM_KILLFOCUS) {
    data[Value("x")] = Value(GET_X_LPARAM(lparam));
    data[Value("y")] = Value(GET_Y_LPARAM(lparam));
  }
  POINT cursor{};
  if (GetCursorPos(&cursor)) {
    data[Value("cursorScreenX")] = Value(static_cast<int64_t>(cursor.x));
    data[Value("cursorScreenY")] = Value(static_cast<int64_t>(cursor.y));
  }
  channel_->InvokeMethod("nativeInput", std::make_unique<Value>(data));
}

bool WindowsTouchInput::ReactivateHover() {
  CURSORINFO cursor{};
  cursor.cbSize = sizeof(cursor);
  const bool known = GetCursorInfo(&cursor) != FALSE;
  const auto decision = hover_policy_.Reactivate(
      known ? &cursor.ptScreenPos : nullptr,
      known && (cursor.flags & CURSOR_SUPPRESSED) != 0);
  if (decision.clear_hover) ClearMouseHover("clearReentryHover");
  return decision.clear_hover;
}

void WindowsTouchInput::ClearMouseHover(const char* action) {
  if (!IsWindow(view_.handle)) return;
  // Flutter classifies WM_MOUSELEAVE using the current message's extra info.
  // A touch-originated leave would otherwise be ignored as touch promotion.
  const LPARAM previous = SetMessageExtraInfo(0);
  RecordMessage(view_.handle, WM_MOUSELEAVE, 0, 0, false, action);
  SendMessage(view_.handle, WM_MOUSELEAVE, 0, 0);
  SetMessageExtraInfo(previous);
}

flutter::EncodableMap WindowsTouchInput::CursorSnapshot() {
  using Value = flutter::EncodableValue;
  CURSORINFO cursor{};
  cursor.cbSize = sizeof(cursor);
  const bool known = GetCursorInfo(&cursor) != FALSE;
  flutter::EncodableMap data{{Value("known"), Value(known)}};
  if (!known) {
    data[Value("error")] = Value(static_cast<int64_t>(GetLastError()));
    return data;
  }
  POINT client = cursor.ptScreenPos;
  const bool converted = ScreenToClient(view_.handle, &client) != FALSE;
  RECT bounds{};
  const bool in_view = converted && GetClientRect(view_.handle, &bounds) &&
      PtInRect(&bounds, client);
  const HWND foreground = GetForegroundWindow();
  data[Value("screenX")] = Value(static_cast<int64_t>(cursor.ptScreenPos.x));
  data[Value("screenY")] = Value(static_cast<int64_t>(cursor.ptScreenPos.y));
  data[Value("flags")] = Value(static_cast<int64_t>(cursor.flags));
  data[Value("showing")] = Value((cursor.flags & CURSOR_SHOWING) != 0);
  data[Value("suppressed")] = Value((cursor.flags & CURSOR_SUPPRESSED) != 0);
  data[Value("handle")] = Value(static_cast<int64_t>(reinterpret_cast<INT_PTR>(cursor.hCursor)));
  data[Value("inViewBounds")] = Value(in_view);
  data[Value("foreground")] = Value(foreground == parent_.handle || IsChild(parent_.handle, foreground));
  data[Value("captureIsView")] = Value(GetCapture() == view_.handle);
  data[Value("viewDpi")] = Value(static_cast<int64_t>(GetDpiForWindow(view_.handle)));
  if (converted) {
    data[Value("viewX")] = Value(static_cast<int64_t>(client.x));
    data[Value("viewY")] = Value(static_cast<int64_t>(client.y));
  }
  return data;
}

void WindowsTouchInput::RecordCursor() {
  if (!logging_) return;
  using Value = flutter::EncodableValue;
  auto snapshot = CursorSnapshot();
  if (snapshot.find(Value("foreground")) == snapshot.end() ||
      !std::get<bool>(snapshot.at(Value("foreground")))) return;
  const auto now = GetTickCount64();
  if (snapshot == last_cursor_ && now - last_cursor_ms_ < 2000) return;
  last_cursor_ = snapshot;
  last_cursor_ms_ = now;
  snapshot[Value("touchMode")] = Value(hover_policy_.touch_mode());
  snapshot[Value("awaitingMouseActivity")] = Value(hover_policy_.awaiting_mouse_activity());
  snapshot[Value("tickMs")] = Value(static_cast<int64_t>(now));
  channel_->InvokeMethod("nativeCursor", std::make_unique<Value>(snapshot));
}
