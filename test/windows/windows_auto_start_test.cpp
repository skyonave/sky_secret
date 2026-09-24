#include "../../windows/runner/windows_auto_start.h"

#include <cstdio>

namespace {
int failures = 0;
void Check(bool passed, const char* label) {
  if (passed) return;
  std::fprintf(stderr, "FAIL: %s\n", label);
  ++failures;
}
}

int main() {
  const auto path = L"Software\\SkySecretTests\\AutoStart-" + std::to_wstring(GetCurrentProcessId());
  const std::wstring executable = L"C:\\Test Folder\\\u0421\u0435\u0439\u0444\\SkySecret.exe";
  WindowsAutoStart startup(executable, path);
  bool enabled = true;
  Check(startup.Read(&enabled) == ERROR_SUCCESS && !enabled, "missing registration defaults off");
  Check(startup.Set(false) == ERROR_SUCCESS, "disable missing registration");
  Check(startup.Set(true) == ERROR_SUCCESS, "enable registration");
  Check(startup.Read(&enabled) == ERROR_SUCCESS && enabled, "read registration");
  WindowsAutoStart reopened(executable, path);
  Check(reopened.Read(&enabled) == ERROR_SUCCESS && enabled, "registration survives service recreation");
  wchar_t command[261]{};
  DWORD bytes = sizeof(command);
  Check(RegGetValueW(HKEY_CURRENT_USER, path.c_str(), L"SkySecret", RRF_RT_REG_SZ,
      nullptr, command, &bytes) == ERROR_SUCCESS, "read raw command");
  Check(std::wstring(command) == L"\"" + executable + L"\"", "quoted unicode executable without arguments");
  WindowsAutoStart moved(L"C:\\Other Folder\\SkySecret.exe", path);
  Check(moved.Read(&enabled) == ERROR_SUCCESS && !enabled, "moved executable requires registration");
  Check(moved.Set(true) == ERROR_SUCCESS, "update moved executable");
  Check(startup.Read(&enabled) == ERROR_SUCCESS && !enabled, "old executable no longer registered");
  Check(WindowsAutoStart(L"", path).Set(true) == ERROR_INVALID_PARAMETER, "reject empty path");
  Check(WindowsAutoStart(std::wstring(259, L'a'), path).Set(true) == ERROR_INVALID_PARAMETER, "reject long command");
  Check(WindowsAutoStart(L"C:\\bad\"path.exe", path).Set(true) == ERROR_INVALID_PARAMETER, "reject quotes");
  Check(moved.Read(&enabled) == ERROR_SUCCESS && enabled, "invalid writes preserve registration");
  HKEY key = nullptr;
  Check(RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS, "open test key");
  if (key) {
    DWORD neighbor = 42;
    Check(RegSetValueExW(key, L"OtherApp", 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&neighbor), sizeof(neighbor)) == ERROR_SUCCESS, "create neighbor");
    Check(RegSetValueExW(key, L"SkySecret", 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&neighbor), sizeof(neighbor)) == ERROR_SUCCESS, "create malformed registration");
    Check(startup.Read(&enabled) != ERROR_SUCCESS && !enabled, "surface malformed registry value");
    Check(startup.Set(false) == ERROR_SUCCESS, "remove malformed registration");
    Check(startup.Read(&enabled) == ERROR_SUCCESS && !enabled, "disabled registration");
    bytes = sizeof(neighbor);
    neighbor = 0;
    Check(RegGetValueW(HKEY_CURRENT_USER, path.c_str(), L"OtherApp", RRF_RT_REG_DWORD,
        nullptr, &neighbor, &bytes) == ERROR_SUCCESS && neighbor == 42, "preserve other applications");
    RegCloseKey(key);
  }
  Check(!WindowsAutoStart::ExecutablePath().empty(), "resolve executable path");
  Check(RegDeleteKeyW(HKEY_CURRENT_USER, path.c_str()) == ERROR_SUCCESS, "remove synthetic key");
  std::printf("Windows autostart: %s\n", failures == 0 ? "PASS" : "FAIL");
  return failures == 0 ? 0 : 1;
}
