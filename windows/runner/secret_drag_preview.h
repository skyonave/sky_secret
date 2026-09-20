#ifndef RUNNER_SECRET_DRAG_PREVIEW_H_
#define RUNNER_SECRET_DRAG_PREVIEW_H_

#include <windows.h>
#include <string>

class SecretDragPreview {
 public:
  SecretDragPreview(HWND owner, std::wstring title);
  ~SecretDragPreview();
  bool valid() const { return window_ != nullptr; }
  void Update(POINT point, const std::wstring& label, bool ready);
  void Hide();

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  void Paint();
  HWND window_ = nullptr;
  std::wstring title_;
  std::wstring label_;
  bool ready_ = false;
  UINT dpi_ = 0;
  HFONT title_font_ = nullptr;
  HFONT label_font_ = nullptr;
};

#endif
