#ifndef RUNNER_WINDOWS_TOUCH_INPUT_H_
#define RUNNER_WINDOWS_TOUCH_INPUT_H_

#include <windows.h>
#include <commctrl.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Keep the decision independent of HWNDs so mouse/touch interleaving can be
// tested without manufacturing hardware input or changing the user's cursor.
class WindowsTouchHoverPolicy {
 public:
  struct Decision { bool clear_hover = false; bool suppress_move = false; };
  Decision Handle(UINT message, WPARAM wparam, POINTER_INPUT_TYPE pointer_type,
                  bool source_known, INPUT_MESSAGE_SOURCE source,
                  LPARAM extra_info, const POINT* screen_position = nullptr);
  Decision Reactivate(const POINT* cursor_position, bool cursor_suppressed);
  bool touch_mode() const { return touch_mode_; }
  bool awaiting_mouse_activity() const { return awaiting_mouse_activity_; }

 private:
  bool touch_mode_ = false;
  WPARAM mouse_buttons_ = 0;
  bool awaiting_mouse_activity_ = false;
  bool reentry_position_known_ = false;
  POINT reentry_position_{};
};

// Flutter already recognizes raw touch gestures. Prevent Windows from also
// converting a long press into a mouse right-click on the same Flutter view.
class WindowsTouchInput {
 public:
  WindowsTouchInput(flutter::BinaryMessenger* messenger, HWND parent, HWND view);
  ~WindowsTouchInput();

 private:
  struct WindowState {
    HWND handle;
    HANDLE previous_tablet_property;
    bool property_set;
    bool subclass_set;
    const char* role;
  };

  void ConfigureWindow(WindowState& window);
  void RestoreWindow(const WindowState& window);
  void RecordMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                     bool suppressed = false, const char* action = nullptr);
  flutter::EncodableMap CursorSnapshot();
  void RecordCursor();
  void ClearMouseHover(const char* action);
  bool ReactivateHover();
  static LRESULT CALLBACK SubclassProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam, UINT_PTR subclass_id,
                                       DWORD_PTR reference_data);

  WindowState parent_;
  WindowState view_;
  flutter::EncodableMap configuration_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool logging_ = false;
  ULONGLONG last_move_ms_ = 0;
  UINT_PTR cursor_timer_ = 0;
  ULONGLONG last_cursor_ms_ = 0;
  flutter::EncodableMap last_cursor_;
  WindowsTouchHoverPolicy hover_policy_;
};

#endif  // RUNNER_WINDOWS_TOUCH_INPUT_H_
