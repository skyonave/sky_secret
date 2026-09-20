#ifndef RUNNER_PROJECT_PROCESS_ARGUMENTS_H_
#define RUNNER_PROJECT_PROCESS_ARGUMENTS_H_
#include <string>
#include <cwctype>

inline std::wstring ProjectQuoteArgument(const std::wstring& value) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (const auto c : value) {
    if (c == L'\\') { ++slashes; continue; }
    result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
    result += c;
    slashes = 0;
  }
  result.append(slashes * 2, L'\\');
  return result + L'"';
}

inline bool ProjectAbsolutePath(const std::wstring& path) {
  return path.size() >= 3 && ((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z')) &&
      path[1] == L':' && (path[2] == L'\\' || path[2] == L'/') && path.find(L'\0') == std::wstring::npos;
}

inline bool ProjectVariableName(const std::wstring& name) {
  if (name.empty() || name.size() > 128) return false;
  for (size_t i = 0; i < name.size(); ++i) {
    const auto c = name[i];
    if (c == L'_' || (c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') || (i > 0 && c >= L'0' && c <= L'9')) continue;
    return false;
  }
  return true;
}
#endif
