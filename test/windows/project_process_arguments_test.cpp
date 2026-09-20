#include <windows.h>
#include <shellapi.h>
#include <cstdio>
#include <vector>
#include "../../windows/runner/project_process_arguments.h"

int main() {
  const std::vector<std::wstring> values{L"", L"plain", L"two words", L"a\"b", L"C:\\path with spaces\\", L"x&echo %TOKEN%", L"тест", L"\\\\\"end\\"};
  std::wstring command = L"test.exe";
  for (const auto& value : values) command += L" " + ProjectQuoteArgument(value);
  int count = 0;
  auto parsed = CommandLineToArgvW(command.c_str(), &count);
  if (!parsed || count != static_cast<int>(values.size()) + 1) return 1;
  for (size_t i = 0; i < values.size(); ++i) if (values[i] != parsed[i + 1]) return 2;
  LocalFree(parsed);
  if (!ProjectAbsolutePath(L"C:\\Program Files\\runtime.exe") || ProjectAbsolutePath(L"runtime.exe") || ProjectAbsolutePath(L"\\\\server\\runtime.exe")) return 3;
  if (!ProjectVariableName(L"BOT_TOKEN_2") || ProjectVariableName(L"2TOKEN") || ProjectVariableName(L"A=B") || ProjectVariableName(L"")) return 4;
  std::puts("Project argument quoting and input validation passed; no programs launched");
  return 0;
}
