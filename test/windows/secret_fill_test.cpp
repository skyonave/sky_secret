#include "../../windows/runner/secret_fill.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <wincrypt.h>
#include <oleacc.h>
#include <wrl/implements.h>
#include <UIAutomationCore.h>
#include <thread>
#include <chrono>

namespace {
void Check(bool condition, const char* description) {
  if (condition) return;
  std::fprintf(stderr, "FAILED: %s\n", description);
  std::exit(1);
}

class SyntheticAccessibleIdentity final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IAccIdentity> {
 public:
  explicit SyntheticAccessibleIdentity(DWORD id, HRESULT status = S_OK) : id_(id), status_(status) {}
  HRESULT STDMETHODCALLTYPE GetIdentityString(DWORD child, BYTE** identity, DWORD* length) override {
    if (!identity || !length) return E_POINTER;
    *identity = nullptr;
    *length = 0;
    if (status_ != S_OK) return status_;
    const DWORD values[] = {id_, child};
    *identity = static_cast<BYTE*>(CoTaskMemAlloc(sizeof(values)));
    if (!*identity) return E_OUTOFMEMORY;
    memcpy(*identity, values, sizeof(values));
    *length = sizeof(values);
    return S_OK;
  }
 private:
  DWORD id_;
  HRESULT status_;
};

class SyntheticExtendedIdentity final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IAccessibleEx> {
 public:
  explicit SyntheticExtendedIdentity(LONG id) : id_(id) {}
  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY** result) override {
    if (!result) return E_POINTER;
    *result = SafeArrayCreateVector(VT_I4, 0, 2);
    if (!*result) return E_OUTOFMEMORY;
    LONG index = 0;
    LONG scope = 23;
    SafeArrayPutElement(*result, &index, &scope);
    index = 1;
    return SafeArrayPutElement(*result, &index, &id_);
  }
  HRESULT STDMETHODCALLTYPE GetObjectForChild(LONG, IAccessibleEx** result) override {
    *result = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetIAccessiblePair(IAccessible**, LONG*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE ConvertReturnedElement(IRawElementProviderSimple*, IAccessibleEx**) override {
    return E_NOTIMPL;
  }
 private:
  LONG id_;
};

void CheckAccessibleIdentity() {
  const auto first = Microsoft::WRL::Make<SyntheticAccessibleIdentity>(17);
  const auto same = Microsoft::WRL::Make<SyntheticAccessibleIdentity>(17);
  const auto different = Microsoft::WRL::Make<SyntheticAccessibleIdentity>(18);
  const auto unavailable = Microsoft::WRL::Make<SyntheticAccessibleIdentity>(17, E_NOTIMPL);
  Check(first.Get() != same.Get(), "fixture uses different COM objects for one field");
  Check(SameAccessibleIdentity(first.Get(), 0, same.Get(), 0),
        "fresh accessibility wrappers for the same field must pass drop revalidation");
  Check(!SameAccessibleIdentity(first.Get(), 0, different.Get(), 0), "different fields are rejected");
  Check(!SameAccessibleIdentity(first.Get(), 0, same.Get(), 1), "different children are rejected");
  Check(!SameAccessibleIdentity(first.Get(), 0, unavailable.Get(), 0), "missing identity is not guessed");
  Check(!SameAccessibleIdentity(nullptr, 0, same.Get(), 0), "missing object is rejected");
  Check(SameAccessibleIdentity(first.Get(), 0, first.Get(), 0), "same live COM object remains supported");
  const auto chrome_first = Microsoft::WRL::Make<SyntheticExtendedIdentity>(31);
  const auto chrome_same = Microsoft::WRL::Make<SyntheticExtendedIdentity>(31);
  const auto chrome_other = Microsoft::WRL::Make<SyntheticExtendedIdentity>(32);
  Check(SameAccessibleIdentity(chrome_first.Get(), 0, chrome_same.Get(), 0),
        "IAccessibleEx runtime identity supports Chromium-style wrappers without IAccIdentity");
  Check(!SameAccessibleIdentity(chrome_first.Get(), 0, chrome_other.Get(), 0),
        "different runtime identities remain rejected");
  Check(!SameAccessibleIdentity(chrome_first.Get(), 0, chrome_same.Get(), 1),
        "missing child identity cannot fall back to parent runtime id");
}

std::shared_ptr<VirtualFilePayload> Payload(const std::string& plain) {
  std::vector<uint8_t> bytes(plain.begin(), plain.end());
  bytes.resize(((bytes.size() + 15) / 16) * 16);
  for (size_t offset = 0; offset < bytes.size(); offset += VirtualFilePayload::kChunkSize) {
    const auto count = std::min(VirtualFilePayload::kChunkSize, bytes.size() - offset);
    Check(CryptProtectMemory(bytes.data() + offset, static_cast<DWORD>(count), CRYPTPROTECTMEMORY_SAME_PROCESS) != FALSE,
          "protect synthetic credential");
  }
  return std::make_shared<VirtualFilePayload>(L"credential", plain.size(), std::move(bytes));
}

std::shared_ptr<SecretFillJob> Job(const std::string& username, const std::string& password) {
  auto job = std::make_shared<SecretFillJob>();
  job->username = Payload(username);
  job->password = Payload(password);
  job->deadline = GetTickCount64() + 5000;
  return job;
}

struct Delivery {
  int calls = 0;
  std::wstring value;
};

class SyntheticTarget final : public SecretFillTarget {
 public:
  SyntheticTarget(SecretField field, int identity, Delivery* delivery, HRESULT status = S_OK)
      : field_(field), identity_(identity), delivery_(delivery), status_(status) {}
  SecretField Field() const override { return field_; }
  bool Same(const SecretFillTarget& other) const override {
    const auto* target = dynamic_cast<const SyntheticTarget*>(&other);
    return target && identity_ == target->identity_;
  }
  HRESULT SetValue(BSTR value) override {
    ++delivery_->calls;
    delivery_->value = value;
    return status_;
  }
 private:
  SecretField field_;
  int identity_;
  Delivery* delivery_;
  HRESULT status_;
};

struct PairScenario {
  std::vector<SecretField> writes;
  std::vector<std::wstring> values;
  std::shared_ptr<SecretFillJob> job = Job("synthetic-login", "synthetic-password");
  bool available = true;
  bool cancel_after_login = false;
  bool change_after_login = false;
  bool reject_password = false;
};

class PairTarget final : public SecretFillTarget {
 public:
  PairTarget(SecretField field, PairScenario* scenario, int identity = 0)
      : field_(field), scenario_(scenario), identity_(identity) {}
  SecretField Field() const override { return field_; }
  bool Same(const SecretFillTarget& other) const override {
    const auto* target = dynamic_cast<const PairTarget*>(&other);
    return target && field_ == target->field_ && scenario_ == target->scenario_ && identity_ == target->identity_;
  }
  std::unique_ptr<SecretFillTarget> Partner() const override {
    if (!scenario_->available) return nullptr;
    const auto other = field_ == SecretField::username ? SecretField::password : SecretField::username;
    const int identity = scenario_->change_after_login && !scenario_->writes.empty() ? 1 : 0;
    return std::make_unique<PairTarget>(other, scenario_, identity);
  }
  HRESULT SetValue(BSTR value) override {
    scenario_->writes.push_back(field_);
    scenario_->values.push_back(value);
    if (field_ == SecretField::username && scenario_->cancel_after_login) scenario_->job->Revoke();
    return field_ == SecretField::password && scenario_->reject_password ? E_FAIL : S_OK;
  }
 private:
  SecretField field_;
  PairScenario* scenario_;
  int identity_;
};

void CheckPairs() {
  {
    PairScenario scenario;
    scenario.job->Move({10, 10}, nullptr);
    std::thread worker([&] {
      RunSecretDrag(scenario.job, [&](POINT, HWND, const SecretFillTarget*) {
        return std::make_unique<PairTarget>(SecretField::password, &scenario);
      });
    });
    const auto deadline = GetTickCount64() + 2000;
    while (scenario.job->Feedback() != SecretField::pair && GetTickCount64() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    const auto feedback = scenario.job->Feedback();
    char byte = 0;
    ULONG read = 0;
    const auto status = scenario.job->password->Read(0, &byte, 1, &read);
    scenario.job->Revoke();
    worker.join();
    Check(feedback == SecretField::pair && scenario.writes.empty() && FAILED(status) && read == 0,
          "pair preview performs no writes and never authorizes credential decoding");
  }
  for (const auto field : {SecretField::username, SecretField::password}) {
    PairScenario scenario;
    const auto result = FillResolvedSecret(*scenario.job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget*) {
      return std::make_unique<PairTarget>(field, &scenario);
    });
    Check(result == SecretFillResult::filled &&
          scenario.writes == std::vector<SecretField>{SecretField::username, SecretField::password},
          "dropping onto either field fills login then password");
    Check(scenario.values == std::vector<std::wstring>{L"synthetic-login", L"synthetic-password"},
          "each member of a pair receives only its own credential");
  }
  for (const auto field : {SecretField::username, SecretField::password}) {
    PairScenario scenario;
    scenario.available = false;
    const auto result = FillResolvedSecret(*scenario.job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget*) {
      return std::make_unique<PairTarget>(field, &scenario);
    });
    Check(result == SecretFillResult::filled && scenario.writes == std::vector<SecretField>{field},
          "unresolved pair preserves single-field fill");
  }
  {
    PairScenario scenario;
    scenario.job = Job("", "synthetic-password");
    const auto result = FillResolvedSecret(*scenario.job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget*) {
      return std::make_unique<PairTarget>(SecretField::password, &scenario);
    });
    Check(result == SecretFillResult::filled && scenario.writes == std::vector<SecretField>{SecretField::password},
          "missing login preserves password fill without clearing the other field");
  }
  for (int mode = 0; mode < 3; ++mode) {
    PairScenario scenario;
    scenario.cancel_after_login = mode == 0;
    scenario.change_after_login = mode == 1;
    scenario.reject_password = mode == 2;
    const auto result = FillResolvedSecret(*scenario.job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget*) {
      return std::make_unique<PairTarget>(SecretField::password, &scenario);
    });
    Check(result == SecretFillResult::partial && scenario.writes.size() == (mode == 2 ? 2 : 1),
          "lock, replaced companion or rejected second write report partial completion without retry");
  }
  Delivery delivery;
  SyntheticTarget selected(SecretField::password, 2, &delivery);
  for (int mode = 0; mode < 5; ++mode) {
    std::vector<std::unique_ptr<SecretFillTarget>> candidates;
    candidates.push_back(std::make_unique<SyntheticTarget>(
        mode == 1 ? SecretField::password : SecretField::username, 1, &delivery));
    candidates.push_back(std::make_unique<SyntheticTarget>(SecretField::password, mode == 2 ? 3 : 2, &delivery));
    if (mode == 3) candidates.push_back(std::make_unique<SyntheticTarget>(SecretField::username, 4, &delivery));
    if (mode == 4) candidates.pop_back();
    auto partner = SelectSecretPartner(selected, std::move(candidates));
    Check((partner != nullptr) == (mode == 0),
          "pair selection requires exactly one login, one password and the actual hovered field");
  }
}

void CheckTargetResolution() {
  {
    auto job = Job("user", "password");
    Delivery delivery;
    int calls = 0;
    job->Move({10, 10}, nullptr);
    RunSecretDrag(job, [&](POINT, HWND, const SecretFillTarget* previous) {
      ++calls;
      if (calls == 1) job->Move({10, 10}, nullptr, true);
      else Check(previous != nullptr, "drop keeps the recognized hover target for revalidation");
      return std::make_unique<SyntheticTarget>(SecretField::password, 1, &delivery);
    });
    Check(calls == 2 && job->result == SecretFillResult::filled && delivery.calls == 1,
          "hover to drop preserves the field and writes once after revalidation");
  }
  for (const auto field : {SecretField::username, SecretField::password}) {
    auto job = Job("synthetic-user", "synthetic-password");
    Delivery delivery;
    int calls = 0;
    const auto result = FillResolvedSecret(*job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget* previous) {
      ++calls;
      Check((calls == 1) == (previous == nullptr), "revalidation retains the selected provider");
      return std::make_unique<SyntheticTarget>(field, 1, &delivery);
    });
    Check(result == SecretFillResult::filled && calls == 2 && delivery.calls == 1,
          "drop resolves and revalidates exactly once before writing");
    Check(delivery.value == (field == SecretField::password ? L"synthetic-password" : L"synthetic-user"),
          "resolved field receives selected credential only");
  }
  for (int mode = 0; mode < 4; ++mode) {
    auto job = Job("user", "password");
    Delivery delivery;
    int calls = 0;
    const auto result = FillResolvedSecret(*job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget* previous) -> std::unique_ptr<SecretFillTarget> {
      const bool second = ++calls == 2;
      if (second && mode == 0) return nullptr;
      if (second && mode == 3) job->Revoke();
      return std::make_unique<SyntheticTarget>(second && mode == 1 ? SecretField::username : SecretField::password,
          second && mode == 2 ? 2 : 1, &delivery);
    });
    Check(result != SecretFillResult::filled && delivery.calls == 0,
          "disappearance, changed field type, changed identity and lock prevent writing");
  }
  {
    auto job = Job("", "password");
    Delivery delivery;
    const auto result = FillResolvedSecret(*job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget* previous) {
      return std::make_unique<SyntheticTarget>(SecretField::username, 1, &delivery);
    });
    Check(result == SecretFillResult::missing_value && delivery.calls == 0, "missing login never submits password");
  }
  for (const HRESULT status : {E_FAIL, S_FALSE}) {
    auto job = Job("user", "password");
    Delivery delivery;
    const auto result = FillResolvedSecret(*job, {}, nullptr, [&](POINT, HWND, const SecretFillTarget* previous) {
      return std::make_unique<SyntheticTarget>(SecretField::password, 1, &delivery, status);
    });
    Check(result == SecretFillResult::failed && delivery.calls == 1, "failed setter is not retried with another method");
  }
  {
    auto job = Job("user", "password");
    Delivery delivery;
    int probes = 0;
    job->Move({10, 10}, nullptr);
    RunSecretDrag(job, [&](POINT, HWND, const SecretFillTarget* previous) {
      Check(delivery.calls == 0, "hover never writes values");
      if (++probes == 1) {
        job->Move({20, 20}, nullptr);
      } else {
        Check(job->Feedback() == SecretField::unknown, "old hover result cannot label new position");
        job->Revoke();
      }
      return std::make_unique<SyntheticTarget>(SecretField::password, 1, &delivery);
    });
    Check(probes == 2 && delivery.calls == 0, "hover cancellation ends worker without delivering secrets");
  }
  Check(ClassifyAccessibleSecretField(ROLE_SYSTEM_TEXT, 0) == SecretField::username,
        "legacy text control selects username");
  Check(ClassifyAccessibleSecretField(ROLE_SYSTEM_TEXT, STATE_SYSTEM_PROTECTED) == SecretField::password,
        "legacy protected text control selects password");
  for (const LONG state : {STATE_SYSTEM_READONLY, STATE_SYSTEM_UNAVAILABLE, STATE_SYSTEM_INVISIBLE, STATE_SYSTEM_OFFSCREEN}) {
    Check(ClassifyAccessibleSecretField(ROLE_SYSTEM_TEXT, state | STATE_SYSTEM_PROTECTED) == SecretField::unknown,
          "legacy unavailable or readonly field is rejected");
  }
  Check(ClassifyAccessibleSecretField(ROLE_SYSTEM_PUSHBUTTON, STATE_SYSTEM_PROTECTED) == SecretField::unknown,
        "legacy non-text target is rejected even when marked protected");
}
}

int main() {
  CheckPairs();
  CheckAccessibleIdentity();
  CheckTargetResolution();
  {
    const auto job = Job("synthetic-user", "synthetic-password");
    SecretFillValue unknown;
    Check(unknown.Read(*job, SecretField::unknown) == SecretFillResult::unsupported && !unknown.value(),
          "unknown target never receives a credential");
    SecretFillValue username;
    Check(username.Read(*job, SecretField::username) == SecretFillResult::filled &&
          std::wstring(username.value()) == L"synthetic-user", "normal field selects only username");
    SecretFillValue password;
    Check(password.Read(*job, SecretField::password) == SecretFillResult::filled &&
          std::wstring(password.value()) == L"synthetic-password", "password field selects only password");
    job->Revoke();
    SecretFillValue late;
    Check(late.Read(*job, SecretField::password) == SecretFillResult::cancelled && !late.value(),
          "revocation forbids late decoding");
    Check(!job->username->available() && !job->password->available(), "both encrypted payloads revoked");
  }
  for (const auto field : {SecretField::username, SecretField::password}) {
    const auto job = field == SecretField::username ? Job("", "synthetic-password") : Job("synthetic-user", "");
    SecretFillValue value;
    Check(value.Read(*job, field) == SecretFillResult::missing_value && !value.value(),
          "empty selected value never falls back to the other credential");
  }
  {
    const auto job = Job("user", "synthetic-\xD0\xAF-\xF0\x9F\xA7\xAA");
    SecretFillValue value;
    Check(value.Read(*job, SecretField::password) == SecretFillResult::filled &&
          std::wstring(value.value()) == L"synthetic-\x042F-\xD83E\xDDEA", "UTF-8 preserved including surrogate pair");
  }
  for (const auto& invalid : {std::string("a\0b", 3), std::string("\xFF", 1), std::string(65537, 'x')}) {
    const auto job = Job("user", invalid);
    SecretFillValue value;
    Check(value.Read(*job, SecretField::password) == SecretFillResult::failed && !value.value(),
          "NUL, invalid UTF-8 and oversized values rejected");
  }
  {
    const auto job = Job("user", std::string(33001, 'x'));
    SecretFillValue value;
    Check(value.Read(*job, SecretField::password) == SecretFillResult::filled && SysStringLen(value.value()) == 33001,
          "multiple protected chunks decode without truncation");
  }
  {
    const auto job = Job("user", "password");
    job->deadline = GetTickCount64();
    SecretFillValue value;
    Check(value.Read(*job, SecretField::password) == SecretFillResult::cancelled && !value.value(),
          "expired operation cannot decode");
  }
  std::puts("Secret fill unit checks passed");
}
