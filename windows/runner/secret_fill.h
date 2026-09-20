#ifndef RUNNER_SECRET_FILL_H_
#define RUNNER_SECRET_FILL_H_

#include "virtual_file_data.h"
#include <atomic>
#include <functional>
#include <mutex>

enum class SecretField { unknown, username, password, pair };
enum class SecretFillResult { cancelled, filled, partial, unsupported, target_lost, target_changed, missing_value, failed };

struct SecretFillJob {
  std::shared_ptr<VirtualFilePayload> username;
  std::shared_ptr<VirtualFilePayload> password;
  std::atomic<bool> cancelled{false};
  std::atomic<bool> done{false};
  SecretFillResult result = SecretFillResult::cancelled;
  std::atomic<ULONGLONG> deadline{0};

  std::mutex request_mutex;
  POINT point{};
  HWND target = nullptr;
  uint64_t request = 0;
  uint64_t inspected = 0;
  SecretField feedback = SecretField::unknown;
  bool dropping = false;

  void Revoke();
  bool Allowed() const;
  void Move(POINT position, HWND window, bool drop = false);
  SecretField Feedback();
};

class SecretFillValue {
 public:
  ~SecretFillValue();
  SecretFillValue() = default;
  SecretFillValue(const SecretFillValue&) = delete;
  SecretFillValue& operator=(const SecretFillValue&) = delete;
  SecretFillResult Read(const SecretFillJob& job, SecretField field);
  BSTR value() const { return value_; }

 private:
  BSTR value_ = nullptr;
  size_t size_ = 0;
  bool locked_ = false;
};

class SecretFillTarget {
 public:
  virtual ~SecretFillTarget() = default;
  virtual SecretField Field() const = 0;
  virtual bool Same(const SecretFillTarget& other) const = 0;
  virtual HRESULT SetValue(BSTR value) = 0;
  virtual std::unique_ptr<SecretFillTarget> Partner() const { return nullptr; }
};

using SecretTargetResolver = std::function<std::unique_ptr<SecretFillTarget>(POINT, HWND, const SecretFillTarget*)>;

SecretField ClassifyAccessibleSecretField(LONG role, LONG state);
std::unique_ptr<SecretFillTarget> SelectSecretPartner(const SecretFillTarget& selected,
    std::vector<std::unique_ptr<SecretFillTarget>> candidates);
bool SameAccessibleIdentity(IUnknown* left, LONG left_child, IUnknown* right, LONG right_child);
SecretTargetResolver CreateSecretTargetResolver();
SecretFillResult FillResolvedSecret(const SecretFillJob& job, POINT point, HWND target,
                                    const SecretTargetResolver& resolve, const SecretFillTarget* hovered = nullptr);
void RunSecretDrag(const std::shared_ptr<SecretFillJob>& job, const SecretTargetResolver& resolve);
void RunSecretDragWorker(const std::shared_ptr<SecretFillJob>& job);

#endif
