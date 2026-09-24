#ifndef RUNNER_WINDOWS_AUTO_START_H_
#define RUNNER_WINDOWS_AUTO_START_H_

#include <windows.h>
#include <string>

class WindowsAutoStart {
 public:
  explicit WindowsAutoStart(std::wstring executable,
      std::wstring key_path = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run");
  LSTATUS Read(bool* enabled) const;
  LSTATUS Set(bool enabled) const;
  static std::wstring ExecutablePath();

 private:
  std::wstring executable_;
  std::wstring key_path_;
};

#endif
