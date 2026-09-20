#ifndef RUNNER_SECRET_DRAG_SOURCE_H_
#define RUNNER_SECRET_DRAG_SOURCE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>
#include "secret_fill.h"

class SecretDragSource {
 public:
  explicit SecretDragSource(HWND window) : window_(window) {}
  int64_t Prepare() const;
  void Start(const flutter::EncodableValue* arguments, flutter::MethodResult<flutter::EncodableValue>* result);
  void Cancel(int64_t through);
  void Revoke();
  void Stop();
  void SetSuspended(bool suspended);

 private:
  HWND window_;
  int64_t generation_ = 1;
  int64_t revoked_through_ = 0;
  int64_t active_id_ = 0;
  bool stopped_ = false;
  bool suspended_ = false;
  std::shared_ptr<SecretFillJob> active_;
  std::shared_ptr<SecretFillJob> worker_;
};

#endif
