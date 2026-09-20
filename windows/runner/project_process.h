#ifndef RUNNER_PROJECT_PROCESS_H_
#define RUNNER_PROJECT_PROCESS_H_
#include <flutter/binary_messenger.h>
#include <memory>

class ProjectProcess {
 public:
  explicit ProjectProcess(flutter::BinaryMessenger* messenger);
  ~ProjectProcess();
  void Revoke();
  void Lock();
  void SetSuspended(bool suspended);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
