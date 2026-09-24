#ifndef RUNNER_COMPANION_WINDOW_H_
#define RUNNER_COMPANION_WINDOW_H_

#include <windows.h>
#include <optional>

class CompanionWindow {
 public:
  explicit CompanionWindow(HWND main) : main_(main) {}
  static void CloseAll();
  std::optional<RECT> Bounds() const;
  bool Place(HWND child, double gap, bool above = false, bool configuration = false);
  void Detach();
  bool ReturnFocus(HWND child, HWND target = nullptr) const;
  void OnMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool ValidChild(HWND child) const;
  bool Follow();
  HWND main_;
  HWND child_ = nullptr;
  bool left_ = true;
  bool above_ = false;
  bool configuration_ = false;
  double gap_ = 12;
};

#endif
