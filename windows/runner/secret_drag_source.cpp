#include "secret_drag_source.h"
#include "secret_drag_preview.h"

#include <algorithm>
#include <thread>

namespace {
const flutter::EncodableValue* Argument(const flutter::EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  const auto found = map->find(flutter::EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

int64_t Integer(const flutter::EncodableValue* value) {
  if (!value || (!std::holds_alternative<int32_t>(*value) && !std::holds_alternative<int64_t>(*value))) return -1;
  return value->LongValue();
}

std::wstring Text(const flutter::EncodableMap* args, const char* key) {
  const auto value = Argument(args, key);
  const auto text = value ? std::get_if<std::string>(value) : nullptr;
  if (!text || text->empty() || text->size() > 4096) return {};
  const auto length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
      static_cast<int>(text->size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), static_cast<int>(text->size()), result.data(), length);
  for (auto& character : result) {
    if (character < L' ' || (character >= 0x202A && character <= 0x202E) ||
        (character >= 0x2066 && character <= 0x2069)) character = L' ';
  }
  return result;
}

std::shared_ptr<VirtualFilePayload> Payload(const flutter::EncodableMap* args, const char* key, const char* size_key) {
  const auto size = Integer(Argument(args, size_key));
  const auto value = Argument(args, key);
  const auto data = value ? std::get_if<std::vector<uint8_t>>(value) : nullptr;
  if (size < 0 || size > 65536 || !data || data->size() != static_cast<size_t>(((size + 15) / 16) * 16)) return nullptr;
  return std::make_shared<VirtualFilePayload>(L"credential", static_cast<size_t>(size), *data);
}

bool PumpMessages() {
  MSG message{};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    if (message.message == WM_QUIT) {
      PostQuitMessage(static_cast<int>(message.wParam));
      return false;
    }
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
  return true;
}

bool CancelKeys() {
  return (GetAsyncKeyState(VK_ESCAPE) & 0x8000) || (GetAsyncKeyState(VK_RBUTTON) & 0x8000) ||
      (GetAsyncKeyState(VK_MBUTTON) & 0x8000);
}

const char* ResultName(SecretFillResult result) {
  switch (result) {
    case SecretFillResult::filled: return "filled";
    case SecretFillResult::partial: return "partial";
    case SecretFillResult::unsupported: return "unsupported";
    case SecretFillResult::target_lost: return "targetLost";
    case SecretFillResult::target_changed: return "targetChanged";
    case SecretFillResult::missing_value: return "missingValue";
    case SecretFillResult::failed: return "failed";
    default: return "cancelled";
  }
}
}

int64_t SecretDragSource::Prepare() const {
  return stopped_ || suspended_ || active_ || (worker_ && !worker_->done.load()) || !IsWindowVisible(window_)
      ? -1 : generation_;
}

void SecretDragSource::Start(const flutter::EncodableValue* arguments,
                             flutter::MethodResult<flutter::EncodableValue>* result) {
  const auto args = arguments ? std::get_if<flutter::EncodableMap>(arguments) : nullptr;
  const auto id = Integer(Argument(args, "id"));
  const auto epoch = Integer(Argument(args, "epoch"));
  POINT cursor{};
  RECT client{};
  const bool positioned = GetCursorPos(&cursor) && ScreenToClient(window_, &cursor) && GetClientRect(window_, &client);
  if (id <= revoked_through_ || epoch < 0 || epoch != Prepare() || !positioned || PtInRect(&client, cursor) ||
      !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
    result->Success(flutter::EncodableValue("cancelled"));
    return;
  }
  auto job = std::make_shared<SecretFillJob>();
  job->username = Payload(args, "username", "usernameSize");
  job->password = Payload(args, "password", "passwordSize");
  if (!job->username || !job->password) {
    result->Error("INVALID_DRAG", "Invalid secret transfer");
    return;
  }
  const auto title = Text(args, "title");
  const auto hover = Text(args, "hover");
  const auto login = Text(args, "login");
  const auto password = Text(args, "passwordLabel");
  const auto pair = Text(args, "pairLabel");
  const auto missing_login = Text(args, "missingLogin");
  const auto missing_password = Text(args, "missingPassword");
  if (hover.empty() || login.empty() || password.empty() || pair.empty() || missing_login.empty() || missing_password.empty()) {
    result->Error("INVALID_DRAG", "Invalid drag labels");
    return;
  }
  SecretDragPreview preview(window_, title);
  if (!preview.valid()) {
    result->Success(flutter::EncodableValue("failed"));
    return;
  }
  active_ = job;
  active_id_ = id;
  job->deadline = GetTickCount64() + 120000;
  worker_ = job;
  try {
    std::thread(RunSecretDragWorker, job).detach();
  } catch (...) {
    job->done.store(true);
    Revoke();
    active_.reset();
    active_id_ = 0;
    result->Success(flutter::EncodableValue("failed"));
    return;
  }
  SetCapture(window_);
  auto outcome = SecretFillResult::cancelled;
  bool released = false;
  while (job->Allowed() && !job->done.load() && IsWindowVisible(window_) && GetCapture() == window_ && !CancelKeys()) {
    SetCursor(LoadCursorW(nullptr, IDC_ARROW));
    if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
      released = GetCursorPos(&cursor) != FALSE;
      break;
    }
    if (!GetCursorPos(&cursor)) break;
    job->Move(cursor, GetAncestor(WindowFromPoint(cursor), GA_ROOT));
    const auto field = job->Feedback();
    const auto has_value = field == SecretField::username ? job->username->size > 0 : job->password->size > 0;
    const auto& label = field == SecretField::pair ? pair : field == SecretField::username ? (has_value ? login : missing_login) :
        field == SecretField::password ? (has_value ? password : missing_password) : hover;
    preview.Update(cursor, label, field != SecretField::unknown && has_value);
    if (!PumpMessages()) break;
  }
  preview.Hide();
  if (GetCapture() == window_) ReleaseCapture();
  SetCursor(LoadCursorW(nullptr, IDC_ARROW));
  if (released && job->Allowed()) {
    job->deadline = GetTickCount64() + 5000;
    job->Move(cursor, GetAncestor(WindowFromPoint(cursor), GA_ROOT), true);
    while (!job->done.load() && job->Allowed() && IsWindowVisible(window_) && !CancelKeys()) {
      if (!PumpMessages()) break;
    }
    if (job->done.load()) outcome = job->result;
    else if (!job->cancelled.load() && GetTickCount64() >= job->deadline) outcome = SecretFillResult::failed;
  } else if (job->done.load()) {
    outcome = job->result;
  }
  Revoke();
  active_.reset();
  active_id_ = 0;
  if (!stopped_) result->Success(flutter::EncodableValue(ResultName(outcome)));
}

void SecretDragSource::Cancel(int64_t through) {
  revoked_through_ = std::max(revoked_through_, through);
  if (active_id_ > 0 && active_id_ <= revoked_through_) Revoke();
}

void SecretDragSource::Revoke() {
  ++generation_;
  if (active_) {
    revoked_through_ = std::max(revoked_through_, active_id_);
    active_->Revoke();
  }
}

void SecretDragSource::Stop() {
  stopped_ = true;
  Revoke();
}

void SecretDragSource::SetSuspended(bool suspended) {
  suspended_ = suspended;
  if (suspended) Revoke();
}
