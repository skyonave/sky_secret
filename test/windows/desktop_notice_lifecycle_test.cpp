#include <cstdio>
#include "../../windows/runner/desktop_notice.cpp"

class ShutdownMessenger : public flutter::BinaryMessenger {
 public:
  bool available = true;
  mutable int invalid_calls = 0;
  int registrations = 0;

  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply = nullptr) const override {
    if (!available) ++invalid_calls;
  }

  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler handler) override {
    if (!available) ++invalid_calls;
    if (handler) ++registrations;
  }
};

int main() {
  ShutdownMessenger messenger;
  {
    DesktopNoticePlugin notice(nullptr, &messenger);
    if (messenger.registrations != 1) return 2;
    messenger.available = false;
  }
  if (messenger.invalid_calls != 0) {
    std::fputs("Notification destructor accessed messenger after engine invalidation\n", stderr);
    return 1;
  }
  std::puts("Notification teardown does not access the invalidated engine; no windows created");
  return 0;
}
