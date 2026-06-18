#include "unreal_mirror_ipc.h"

#include <boost/date_time/posix_time/posix_time_types.hpp>
#include <boost/interprocess/ipc/message_queue.hpp>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>

#if defined(_WIN32)
#include <process.h>
#else
#include <unistd.h>
#endif

namespace {

constexpr const char *kServerQueueName = "unreal_mirror_commands";
constexpr size_t kMaxMessageSize = 8192;

std::string make_reply_queue_name() {
#if defined(_WIN32)
  const int pid = _getpid();
#else
  const int pid = getpid();
#endif
  const auto ticks =
      std::chrono::steady_clock::now().time_since_epoch().count();
  std::ostringstream stream;
  stream << "unreal_mirror_reply_" << pid << "_" << ticks;
  return stream.str();
}

void append_field(std::string &message, const std::string &field) {
  message += std::to_string(field.size());
  message += '\n';
  message += field;
  message += '\n';
}

std::string build_request(const std::string &reply_queue_name,
                          const std::string &command, const std::string &path) {
  std::string message = "UMQ1\n";
  append_field(message, reply_queue_name);
  append_field(message, command);
  append_field(message, path);
  return message;
}

void write_response(char *response, size_t response_len,
                    const std::string &text) {
  if (response == nullptr || response_len == 0) {
    return;
  }

  const size_t copy_len =
      (text.size() < response_len - 1) ? text.size() : response_len - 1;
  std::memcpy(response, text.data(), copy_len);
  response[copy_len] = '\0';
}

struct reply_queue_guard {
  explicit reply_queue_guard(const std::string &name) : name(name) {}
  ~reply_queue_guard() {
    boost::interprocess::message_queue::remove(name.c_str());
  }
  std::string name;
};

} // namespace

extern "C" int unreal_mirror_ipc_send_command(const char *command,
                                              const char *path,
                                              unsigned int timeout_ms,
                                              char *response,
                                              size_t response_len) {
  if (command == nullptr || path == nullptr) {
    write_response(response, response_len, "command and path are required");
    return -1;
  }

  try {
    const std::string reply_queue_name = make_reply_queue_name();
    boost::interprocess::message_queue::remove(reply_queue_name.c_str());
    reply_queue_guard guard(reply_queue_name);

    boost::interprocess::message_queue reply_queue(
        boost::interprocess::create_only, reply_queue_name.c_str(), 1,
        kMaxMessageSize);

    boost::interprocess::message_queue server_queue(
        boost::interprocess::open_only, kServerQueueName);

    const std::string request = build_request(reply_queue_name, command, path);
    server_queue.send(request.data(), request.size(), 0);

    std::string buffer(kMaxMessageSize, '\0');
    size_t received_size = 0;
    unsigned int priority = 0;
    const boost::posix_time::ptime deadline =
        boost::posix_time::microsec_clock::universal_time() +
        boost::posix_time::milliseconds(timeout_ms);

    const bool received = reply_queue.timed_receive(
        buffer.data(), buffer.size(), received_size, priority, deadline);
    if (!received) {
      write_response(response, response_len,
                     "timed out waiting for UnrealMirror reply");
      return -2;
    }

    buffer.resize(received_size);
    constexpr const char *ok_prefix = "OK\n";
    constexpr const char *err_prefix = "ERR\n";
    if (buffer.rfind(ok_prefix, 0) == 0) {
      write_response(response, response_len, buffer.substr(3));
      return 0;
    }
    if (buffer.rfind(err_prefix, 0) == 0) {
      write_response(response, response_len, buffer.substr(4));
      return 1;
    }

    write_response(response, response_len, buffer);
    return 1;
  } catch (const std::exception &error) {
    write_response(response, response_len, error.what());
    return -1;
  }
}
