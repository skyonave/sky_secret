#include "project_process.h"
#include "project_process_arguments.h"
#include <windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <vector>
#include <algorithm>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;

std::wstring Wide(const std::string& value) {
  if (value.size() > 65536 || value.find('\0') != std::string::npos) return {};
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring wide(count, 0);
  if (count) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), wide.data(), count);
  return wide;
}

std::wstring Field(const Map& map, const char* name) {
  const auto found = map.find(Value(name));
  if (found == map.end()) return {};
  const auto value = std::get_if<std::string>(&found->second);
  return value ? Wide(*value) : std::wstring{};
}

struct Handle {
  HANDLE value = nullptr;
  explicit Handle(HANDLE handle = nullptr) : value(handle) {}
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE Release() { const auto handle = value; value = nullptr; return handle; }
};

struct Environment {
  std::map<std::wstring, std::wstring> values;
  std::vector<wchar_t> block;
  ~Environment() {
    for (auto& item : values) SecureZeroMemory(item.second.data(), item.second.size() * sizeof(wchar_t));
    SecureZeroMemory(block.data(), block.size() * sizeof(wchar_t));
  }
  bool Read(const Map& args) {
    const auto found = args.find(Value("environment"));
    if (found == args.end()) return false;
    const auto input = std::get_if<Map>(&found->second);
    if (!input || input->size() > 128) return false;
    for (const auto name : {L"SYSTEMROOT", L"WINDIR", L"TEMP", L"TMP", L"PATH", L"USERPROFILE", L"APPDATA", L"LOCALAPPDATA"}) {
      const auto size = GetEnvironmentVariableW(name, nullptr, 0);
      if (size == 0 || size > 8192) continue;
      std::wstring value(size, 0);
      if (GetEnvironmentVariableW(name, value.data(), size) != size - 1) return false;
      value.resize(size - 1);
      values[name] = std::move(value);
    }
    std::map<std::wstring, bool> names;
    for (const auto& item : *input) {
      const auto key = std::get_if<std::string>(&item.first);
      const auto text = std::get_if<std::string>(&item.second);
      if (!key || !text || text->find('\0') != std::string::npos) return false;
      auto name = Wide(*key);
      if (!ProjectVariableName(name)) return false;
      std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
      if (!names.emplace(name, true).second) return false;
      auto value = Wide(*text);
      if (!text->empty() && value.empty()) return false;
      values[name] = std::move(value);
    }
    for (const auto& item : values) {
      block.insert(block.end(), item.first.begin(), item.first.end());
      block.push_back(L'=');
      block.insert(block.end(), item.second.begin(), item.second.end());
      block.push_back(0);
    }
    block.push_back(0);
    return block.size() <= 32767;
  }
};
}

struct ProjectProcess::Impl {
  struct Running { HANDLE job; HANDLE process; };
  std::map<std::string, Running> running;
  flutter::MethodChannel<Value> channel;
  int64_t epoch = 0;
  bool suspended = false;

  explicit Impl(flutter::BinaryMessenger* messenger)
      : channel(messenger, "skysecret/project-launch", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "prepare") {
        if (suspended) result->Success(); else result->Success(Value(epoch));
      } else if (call.method_name() == "revoke") {
        Revoke(); result->Success();
      } else if (call.method_name() == "lock") {
        Lock(); result->Success();
      } else if (call.method_name() == "start") {
        const auto args = std::get_if<Map>(call.arguments());
        result->Success(Value(args && Start(*args)));
      } else if (call.method_name() == "stop") {
        const auto id = std::get_if<std::string>(call.arguments());
        if (id) Stop(*id);
        result->Success();
      } else if (call.method_name() == "status") {
        Map statuses;
        std::vector<std::string> ended;
        for (const auto& item : running) {
          JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info{};
          if (QueryInformationJobObject(item.second.job, JobObjectBasicAccountingInformation, &info, sizeof(info), nullptr) && info.ActiveProcesses > 0) continue;
          DWORD code = 1;
          GetExitCodeProcess(item.second.process, &code);
          statuses[Value(item.first)] = Value(static_cast<int64_t>(code));
          ended.push_back(item.first);
        }
        for (const auto& id : ended) Stop(id);
        result->Success(Value(statuses));
      } else result->NotImplemented();
    });
  }

  void Stop(const std::string& id) {
    const auto item = running.find(id);
    if (item == running.end()) return;
    CloseHandle(item->second.job);
    CloseHandle(item->second.process);
    running.erase(item);
  }

  void Revoke() { ++epoch; while (!running.empty()) Stop(running.begin()->first); }

  void Lock() { ++epoch; }

  bool Start(const Map& args) {
    const auto grant = args.find(Value("epoch"));
    if (suspended || grant == args.end() ||
        !(std::holds_alternative<int32_t>(grant->second) || std::holds_alternative<int64_t>(grant->second)) ||
        grant->second.LongValue() != epoch || running.size() >= 16) return false;
    const auto idValue = args.find(Value("id"));
    if (idValue == args.end()) return false;
    const auto id = std::get_if<std::string>(&idValue->second);
    if (!id || id->empty() || id->size() > 256 || running.count(*id)) return false;
    auto executable = Field(args, "executable");
    auto directory = Field(args, "directory");
    if (!ProjectAbsolutePath(executable) || !ProjectAbsolutePath(directory) || executable.size() < 4 ||
        _wcsicmp(executable.c_str() + executable.size() - 4, L".exe") != 0) return false;
    const auto arguments = args.find(Value("arguments"));
    if (arguments == args.end()) return false;
    const auto list = std::get_if<List>(&arguments->second);
    if (!list || list->size() > 128) return false;
    std::wstring command = ProjectQuoteArgument(executable);
    for (const auto& item : *list) {
      const auto text = std::get_if<std::string>(&item);
      if (!text || text->find('\0') != std::string::npos) return false;
      const auto value = Wide(*text);
      if (!text->empty() && value.empty()) return false;
      command += L" " + ProjectQuoteArgument(value);
    }
    if (command.size() >= 32767) return false;
    Environment environment;
    if (!environment.Read(args)) return false;
    Handle job(CreateJobObjectW(nullptr, nullptr));
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job.value || !SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return false;
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    Handle null(CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, nullptr));
    if (null.value == INVALID_HANDLE_VALUE) return false;
    SIZE_T attributeSize = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attributeSize);
    std::vector<unsigned char> attributes(attributeSize);
    auto attributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributes.data());
    if (!InitializeProcThreadAttributeList(attributeList, 1, 0, &attributeSize)) return false;
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = startup.StartupInfo.hStdOutput = startup.StartupInfo.hStdError = null.value;
    startup.lpAttributeList = attributeList;
    PROCESS_INFORMATION process{};
    const auto created = UpdateProcThreadAttribute(attributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, &null.value, sizeof(HANDLE), nullptr, nullptr) &&
        CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, TRUE,
          CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT,
          environment.block.data(), directory.c_str(), &startup.StartupInfo, &process);
    DeleteProcThreadAttributeList(attributeList);
    if (!created) return false;
    Handle child(process.hProcess);
    Handle thread(process.hThread);
    if (!AssignProcessToJobObject(job.value, child.value) || ResumeThread(thread.value) == static_cast<DWORD>(-1)) {
      TerminateProcess(child.value, 1);
      return false;
    }
    running.emplace(*id, Running{job.Release(), child.Release()});
    return true;
  }
};

ProjectProcess::ProjectProcess(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>(messenger)) {}
ProjectProcess::~ProjectProcess() { Revoke(); }
void ProjectProcess::Revoke() { impl_->Revoke(); }
void ProjectProcess::Lock() { impl_->Lock(); }
void ProjectProcess::SetSuspended(bool suspended) { impl_->suspended = suspended; if (suspended) Lock(); }
