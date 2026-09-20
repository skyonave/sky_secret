#ifndef RUNNER_STARTUP_INDICATOR_H_
#define RUNNER_STARTUP_INDICATOR_H_

#include <windows.h>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>

class StartupIndicator {
 public:
  ~StartupIndicator();
  void Start(const wchar_t* instance_mutex = L"Local\\SecretManager.Desktop.v1.Instance");
  void Labels(std::wstring loading, std::wstring ready, std::wstring failed);
  void Finish(bool success);
  void Stop();

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  void Run();
  void Paint(HWND window);
  void Tick(HWND window);
  std::thread thread_;
  std::atomic<HWND> window_{nullptr};
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  std::wstring loading_ = L"SkySecret";
  std::wstring ready_;
  std::wstring failed_;
  int status_ = 0;
  int displayed_status_ = 0;
  ULONGLONG finished_at_ = 0;
  int phase_ = 0;
};

#endif
