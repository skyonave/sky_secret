#include "windows_auto_start.h"

#include <utility>
#include <vector>

WindowsAutoStart::WindowsAutoStart(std::wstring executable, std::wstring key_path)
    : executable_(std::move(executable)), key_path_(std::move(key_path)) {}

std::wstring WindowsAutoStart::ExecutablePath() {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) return {};
  return std::wstring(buffer.data(), length);
}

LSTATUS WindowsAutoStart::Read(bool* enabled) const {
  *enabled = false;
  wchar_t command[261]{};
  DWORD bytes = sizeof(command);
  const auto status = RegGetValueW(HKEY_CURRENT_USER, key_path_.c_str(), L"SkySecret",
      RRF_RT_REG_SZ, nullptr, command, &bytes);
  if (status == ERROR_FILE_NOT_FOUND) return ERROR_SUCCESS;
  if (status != ERROR_SUCCESS) return status;
  const auto expected = L"\"" + executable_ + L"\"";
  *enabled = !executable_.empty() && CompareStringOrdinal(command, -1, expected.c_str(), -1, TRUE) == CSTR_EQUAL;
  return ERROR_SUCCESS;
}

LSTATUS WindowsAutoStart::Set(bool enabled) const {
  HKEY key = nullptr;
  LSTATUS status;
  if (enabled) {
    const auto command = L"\"" + executable_ + L"\"";
    if (executable_.empty() || executable_.find_first_of(L"\"\r\n") != std::wstring::npos ||
        executable_.find(L'\0') != std::wstring::npos || command.size() > 260) {
      return ERROR_INVALID_PARAMETER;
    }
    status = RegCreateKeyExW(HKEY_CURRENT_USER, key_path_.c_str(), 0, nullptr, 0,
        KEY_SET_VALUE, nullptr, &key, nullptr);
    if (status != ERROR_SUCCESS) return status;
    status = RegSetValueExW(key, L"SkySecret", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegOpenKeyExW(HKEY_CURRENT_USER, key_path_.c_str(), 0, KEY_SET_VALUE, &key);
    if (status == ERROR_FILE_NOT_FOUND) return ERROR_SUCCESS;
    if (status != ERROR_SUCCESS) return status;
    status = RegDeleteValueW(key, L"SkySecret");
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  if (status != ERROR_SUCCESS) return status;
  bool actual = false;
  status = Read(&actual);
  if (status != ERROR_SUCCESS) return status;
  return actual == enabled ? ERROR_SUCCESS : ERROR_INVALID_DATA;
}
