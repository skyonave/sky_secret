#include "secret_fill.h"

#include <chrono>
#include <cstring>
#include <thread>

void SecretFillJob::Revoke() {
  cancelled.store(true);
  if (username) username->Revoke();
  if (password) password->Revoke();
}

bool SecretFillJob::Allowed() const {
  return !cancelled.load() && GetTickCount64() < deadline;
}

void SecretFillJob::Move(POINT position, HWND window, bool drop) {
  std::lock_guard<std::mutex> lock(request_mutex);
  if (dropping) return;
  if (drop || point.x != position.x || point.y != position.y || target != window || request == 0) {
    point = position;
    target = window;
    dropping = drop;
    ++request;
    feedback = SecretField::unknown;
  }
}

SecretField SecretFillJob::Feedback() {
  std::lock_guard<std::mutex> lock(request_mutex);
  return inspected == request ? feedback : SecretField::unknown;
}

SecretFillValue::~SecretFillValue() {
  if (!value_) return;
  SecureZeroMemory(value_, size_);
  if (locked_) VirtualUnlock(value_, size_);
  SysFreeString(value_);
}

SecretFillResult SecretFillValue::Read(const SecretFillJob& job, SecretField field) {
  if (!job.Allowed()) return SecretFillResult::cancelled;
  if (field != SecretField::username && field != SecretField::password) return SecretFillResult::unsupported;
  const auto payload = field == SecretField::password ? job.password : job.username;
  if (!payload || !payload->valid() || payload->size > 65536 || value_) return SecretFillResult::failed;
  if (payload->size == 0) return SecretFillResult::missing_value;
  auto* bytes = static_cast<char*>(VirtualAlloc(nullptr, payload->size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
  if (!bytes) return SecretFillResult::failed;
  const bool locked = VirtualLock(bytes, payload->size) != FALSE;
  auto result = SecretFillResult::failed;
  if (locked) {
    payload->AuthorizeDrop();
    ULONG read = 0;
    const auto status = payload->Read(0, bytes, static_cast<ULONG>(payload->size), &read);
    if (SUCCEEDED(status) && read == payload->size && !memchr(bytes, 0, read)) {
      const auto length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes, static_cast<int>(read), nullptr, 0);
      if (length > 0) {
        value_ = SysAllocStringLen(nullptr, static_cast<UINT>(length));
        size_ = (static_cast<size_t>(length) + 1) * sizeof(wchar_t);
        locked_ = value_ && VirtualLock(value_, size_);
        if (locked_ && MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes, static_cast<int>(read), value_, length)) {
          value_[length] = 0;
          result = job.Allowed() ? SecretFillResult::filled : SecretFillResult::cancelled;
        }
      }
    }
  }
  SecureZeroMemory(bytes, payload->size);
  if (locked) VirtualUnlock(bytes, payload->size);
  VirtualFree(bytes, 0, MEM_RELEASE);
  return result;
}

std::unique_ptr<SecretFillTarget> SelectSecretPartner(const SecretFillTarget& selected,
    std::vector<std::unique_ptr<SecretFillTarget>> candidates) {
  if (candidates.size() != 2 || !candidates[0] || !candidates[1]) return nullptr;
  const auto first = candidates[0]->Field();
  const auto second = candidates[1]->Field();
  if (!((first == SecretField::username && second == SecretField::password) ||
        (first == SecretField::password && second == SecretField::username))) return nullptr;
  for (size_t i = 0; i < 2; ++i) {
    if (selected.Field() == candidates[i]->Field() && selected.Same(*candidates[i])) {
      return std::move(candidates[1 - i]);
    }
  }
  return nullptr;
}

namespace {
bool Complementary(const SecretFillTarget& selected, const SecretFillTarget* partner) {
  if (!partner || selected.Same(*partner)) return false;
  return (selected.Field() == SecretField::username && partner->Field() == SecretField::password) ||
      (selected.Field() == SecretField::password && partner->Field() == SecretField::username);
}

SecretFillResult FillPair(const SecretFillJob& job, POINT point, HWND target, const SecretTargetResolver& resolve,
                         const SecretFillTarget& selected, SecretFillTarget& current, SecretFillTarget& partner) {
  SecretFillValue login;
  SecretFillValue password;
  const auto login_read = login.Read(job, SecretField::username);
  if (login_read != SecretFillResult::filled) return login_read;
  const auto password_read = password.Read(job, SecretField::password);
  if (password_read != SecretFillResult::filled) return password_read;
  if (!job.Allowed()) return SecretFillResult::cancelled;
  auto* login_field = current.Field() == SecretField::username ? &current : &partner;
  if (login_field->SetValue(login.value()) != S_OK) return SecretFillResult::failed;
  if (!job.Allowed()) return SecretFillResult::partial;
  const auto after_login = resolve(point, target, &selected);
  if (!after_login || after_login->Field() != selected.Field() || !selected.Same(*after_login)) {
    return SecretFillResult::partial;
  }
  const auto after_partner = after_login->Partner();
  if (!Complementary(*after_login, after_partner.get()) || after_partner->Field() != partner.Field() ||
      !partner.Same(*after_partner) || !job.Allowed()) return SecretFillResult::partial;
  auto* password_field = after_login->Field() == SecretField::password ? after_login.get() : after_partner.get();
  return password_field->SetValue(password.value()) == S_OK ? SecretFillResult::filled : SecretFillResult::partial;
}
}

SecretFillResult FillResolvedSecret(const SecretFillJob& job, POINT point, HWND target,
                                    const SecretTargetResolver& resolve, const SecretFillTarget* hovered) {
  if (!job.Allowed()) return SecretFillResult::cancelled;
  const auto resolved = hovered ? nullptr : resolve(point, target, nullptr);
  const auto* selected = hovered ? hovered : resolved.get();
  if (!selected || selected->Field() == SecretField::unknown) return SecretFillResult::unsupported;
  const bool has_pair = job.username && job.password && job.username->size > 0 && job.password->size > 0;
  const auto partner = has_pair ? selected->Partner() : nullptr;
  SecretFillValue value;
  const auto decoded = value.Read(job, selected->Field());
  if (decoded != SecretFillResult::filled) return decoded;
  if (!job.Allowed()) return SecretFillResult::cancelled;
  auto current = resolve(point, target, selected);
  if (!current) return SecretFillResult::target_lost;
  if (selected->Field() != current->Field() || !selected->Same(*current)) return SecretFillResult::target_changed;
  if (Complementary(*selected, partner.get()) && job.Allowed()) {
    const auto current_partner = current->Partner();
    if (Complementary(*current, current_partner.get()) && partner->Field() == current_partner->Field() &&
        partner->Same(*current_partner)) {
      return FillPair(job, point, target, resolve, *selected, *current, *current_partner);
    }
    current = resolve(point, target, selected);
    if (!current) return SecretFillResult::target_lost;
    if (selected->Field() != current->Field() || !selected->Same(*current)) return SecretFillResult::target_changed;
  }
  if (!job.Allowed()) return SecretFillResult::cancelled;
  return current->SetValue(value.value()) == S_OK ? SecretFillResult::filled : SecretFillResult::failed;
}

void RunSecretDrag(const std::shared_ptr<SecretFillJob>& job, const SecretTargetResolver& resolve) {
  uint64_t previous = 0;
  ULONGLONG next_probe = 0;
  std::unique_ptr<SecretFillTarget> hovered;
  POINT hovered_point{};
  HWND hovered_window = nullptr;
  while (job->Allowed()) {
    POINT point{};
    HWND target = nullptr;
    uint64_t request = 0;
    bool dropping = false;
    {
      std::lock_guard<std::mutex> lock(job->request_mutex);
      point = job->point;
      target = job->target;
      request = job->request;
      dropping = job->dropping;
    }
    if (dropping) {
      const bool same_position = point.x == hovered_point.x && point.y == hovered_point.y && target == hovered_window;
      job->result = FillResolvedSecret(*job, point, target, resolve, same_position ? hovered.get() : nullptr);
      return;
    }
    if (request > 0 && (request != previous || GetTickCount64() >= next_probe)) {
      hovered = resolve(point, target, nullptr);
      hovered_point = point;
      hovered_window = target;
      auto field = hovered ? hovered->Field() : SecretField::unknown;
      if (hovered && job->Allowed() && job->username->size > 0 && job->password->size > 0) {
        const auto partner = hovered->Partner();
        if (Complementary(*hovered, partner.get())) field = SecretField::pair;
      }
      {
        std::lock_guard<std::mutex> lock(job->request_mutex);
        if (job->Allowed() && request == job->request && !job->dropping) {
          job->feedback = field;
          job->inspected = request;
        }
      }
      previous = request;
      next_probe = GetTickCount64() + 150;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
}

void RunSecretDragWorker(const std::shared_ptr<SecretFillJob>& job) {
  const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (SUCCEEDED(initialized)) {
    try {
      const auto resolve = CreateSecretTargetResolver();
      RunSecretDrag(job, resolve);
    } catch (...) {
      job->result = SecretFillResult::failed;
    }
    CoUninitialize();
  } else {
    job->result = SecretFillResult::failed;
  }
  job->username->Revoke();
  job->password->Revoke();
  job->done.store(true);
}
