#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <map>
#include <vector>
#include <algorithm>
#include <string>
#include <cstdio>
#include <cstdlib>

#define private public
#include "../../windows/runner/project_process.h"
#undef private

namespace {
bool assigned = false;
bool failAssign = false;
bool failCreate = false;
int createdCount = 0;
int resumedCount = 0;
int terminatedCount = 0;
int closedJobs = 0;
DWORD creationFlags = 0;
DWORD jobFlags = 0;
std::wstring capturedCommand;
std::map<std::wstring, std::wstring> capturedEnvironment;
std::vector<std::wstring> inheritedNames;
HANDLE FakeHandle(int id) { return reinterpret_cast<HANDLE>(static_cast<intptr_t>(id)); }
void Check(bool value, const char* message) {
  if (value) return;
  std::fprintf(stderr, "FAILED: %s\n", message);
  std::exit(1);
}
HANDLE WINAPI FakeCreateJob(LPSECURITY_ATTRIBUTES, LPCWSTR) { return FakeHandle(1); }
BOOL WINAPI FakeSetJob(HANDLE, JOBOBJECTINFOCLASS, LPVOID information, DWORD) {
  jobFlags = static_cast<JOBOBJECT_EXTENDED_LIMIT_INFORMATION*>(information)->BasicLimitInformation.LimitFlags;
  return TRUE;
}
BOOL WINAPI FakeClose(HANDLE handle) { if (handle == FakeHandle(1)) ++closedJobs; return TRUE; }
HANDLE WINAPI FakeCreateFile(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE) { return FakeHandle(2); }
BOOL WINAPI FakeInitializeAttributes(LPPROC_THREAD_ATTRIBUTE_LIST list, DWORD, DWORD, PSIZE_T size) {
  *size = 128;
  return list != nullptr;
}
BOOL WINAPI FakeUpdateAttribute(LPPROC_THREAD_ATTRIBUTE_LIST, DWORD, DWORD_PTR attribute, PVOID value, SIZE_T size, PVOID, PSIZE_T) {
  Check(attribute == PROC_THREAD_ATTRIBUTE_HANDLE_LIST && size == sizeof(HANDLE) && *static_cast<HANDLE*>(value) == FakeHandle(2), "only NUL is inherited");
  return TRUE;
}
VOID WINAPI FakeDeleteAttributes(LPPROC_THREAD_ATTRIBUTE_LIST) {}
DWORD WINAPI FakeEnvironment(LPCWSTR name, LPWSTR value, DWORD size) {
  inheritedNames.emplace_back(name);
  if (!value) return 2;
  Check(size == 2, "environment allocation");
  value[0] = L'x'; value[1] = 0;
  return 1;
}
BOOL WINAPI FakeCreateProcess(LPCWSTR application, LPWSTR command, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES,
    BOOL inherit, DWORD flags, LPVOID environment, LPCWSTR directory, LPSTARTUPINFOW startup, LPPROCESS_INFORMATION process) {
  ++createdCount;
  Check(std::wstring(application) == L"C:\\runtime\\node.exe", "explicit executable");
  Check(std::wstring(directory) == L"C:\\repo" && inherit, "working directory and inheritance");
  Check(startup->hStdInput == FakeHandle(2) && startup->hStdOutput == FakeHandle(2) && startup->hStdError == FakeHandle(2), "output is not logged");
  capturedCommand = command;
  creationFlags = flags;
  capturedEnvironment.clear();
  for (auto item = static_cast<const wchar_t*>(environment); *item; item += wcslen(item) + 1) {
    const std::wstring field(item);
    const auto separator = field.find(L'=');
    capturedEnvironment[field.substr(0, separator)] = field.substr(separator + 1);
  }
  if (failCreate) return FALSE;
  process->hProcess = FakeHandle(3); process->hThread = FakeHandle(4);
  assigned = false;
  return TRUE;
}
BOOL WINAPI FakeAssign(HANDLE, HANDLE) { assigned = !failAssign; return assigned; }
DWORD WINAPI FakeResume(HANDLE) { Check(assigned, "process must join the job before executing"); ++resumedCount; return 1; }
BOOL WINAPI FakeTerminate(HANDLE, UINT) { ++terminatedCount; return TRUE; }
}

#define CreateJobObjectW FakeCreateJob
#define SetInformationJobObject FakeSetJob
#define CloseHandle FakeClose
#define CreateFileW FakeCreateFile
#define InitializeProcThreadAttributeList FakeInitializeAttributes
#define UpdateProcThreadAttribute FakeUpdateAttribute
#define DeleteProcThreadAttributeList FakeDeleteAttributes
#define GetEnvironmentVariableW FakeEnvironment
#define CreateProcessW FakeCreateProcess
#define AssignProcessToJobObject FakeAssign
#define ResumeThread FakeResume
#define TerminateProcess FakeTerminate
#include "../../windows/runner/project_process.cpp"

class Messenger final : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply = nullptr) const override {}
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler) override {}
};

int main() {
  Messenger messenger;
  ProjectProcess::Impl process(&messenger);
  Map args{
      {Value("epoch"), Value(int64_t{0})}, {Value("id"), Value("synthetic")},
      {Value("executable"), Value("C:\\runtime\\node.exe")}, {Value("directory"), Value("C:\\repo")},
      {Value("arguments"), Value(List{Value("server.js"), Value("space argument")})},
      {Value("environment"), Value(Map{{Value("API_TOKEN"), Value("synthetic-token")}})},
  };
  Check(process.Start(args), "valid launch accepted");
  Check(resumedCount == 1 && process.running.size() == 1, "managed process retained");
  Check((creationFlags & CREATE_SUSPENDED) && (creationFlags & CREATE_UNICODE_ENVIRONMENT) &&
      (creationFlags & EXTENDED_STARTUPINFO_PRESENT), "required process creation flags");
  Check(jobFlags == JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, "job cannot outlive its manager");
  Check(capturedCommand.find(L"synthetic-token") == std::wstring::npos &&
      capturedEnvironment.at(L"API_TOKEN") == L"synthetic-token", "secret only in environment");
  Check(std::find(inheritedNames.begin(), inheritedNames.end(), L"API_TOKEN") == inheritedNames.end(), "parent secrets not inherited");
  process.Lock();
  Check(closedJobs == 0 && process.running.size() == 1, "vault lock preserves an approved running process");
  process.Revoke();
  Check(closedJobs == 1 && process.running.empty(), "revoke closes the process job");
  Check(!process.Start(args) && createdCount == 1, "stale epoch never starts a process");
  args[Value("epoch")] = Value(int64_t{2});
  process.suspended = true;
  Check(!process.Start(args) && createdCount == 1, "suspended system rejects launches");
  process.suspended = false;
  failAssign = true;
  Check(!process.Start(args) && terminatedCount == 1 && resumedCount == 1, "assignment failure terminates before execution");
  failAssign = false;
  failCreate = true;
  Check(!process.Start(args) && process.running.empty(), "creation failure leaves no managed process");
  failCreate = false;
  args[Value("environment")] = Value(Map{{Value("Token"), Value("one")}, {Value("TOKEN"), Value("two")}});
  const auto previousCreates = createdCount;
  Check(!process.Start(args) && createdCount == previousCreates, "case collisions rejected before launch");
  std::puts("Project process lifecycle unit checks passed (all process APIs mocked)");
}
