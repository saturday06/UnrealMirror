// Copyright Epic Games, Inc. All Rights Reserved.

#include "UnrealMirrorIpcServer.h"

#include "Async/Async.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

#include <cstdlib>
#include <string>
#include <vector>

THIRD_PARTY_INCLUDES_START
#ifdef check
#pragma push_macro("check")
#undef check
#define UE_RESTORE_CHECK_MACRO
#endif
#ifdef verify
#pragma push_macro("verify")
#undef verify
#define UE_RESTORE_VERIFY_MACRO
#endif

#include <boost/date_time/posix_time/posix_time_types.hpp>
#include <boost/interprocess/ipc/message_queue.hpp>

#ifdef UE_RESTORE_VERIFY_MACRO
#pragma pop_macro("verify")
#undef UE_RESTORE_VERIFY_MACRO
#endif
#ifdef UE_RESTORE_CHECK_MACRO
#pragma pop_macro("check")
#undef UE_RESTORE_CHECK_MACRO
#endif
THIRD_PARTY_INCLUDES_END

DEFINE_LOG_CATEGORY_STATIC(LogUnrealMirrorIpc, Log, All);

namespace {

constexpr const char *UnrealMirrorQueueName = "unreal_mirror_commands";
constexpr uint32 MaxQueueMessages = 64;
constexpr uint32 MaxMessageSize = 8192;
constexpr uint8 DummyPngBytes[] = {
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00,
    0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x01, 0x08, 0x04, 0x00, 0x00, 0x00, 0xb5,
    0x1c, 0x0c, 0x02, 0x00, 0x00, 0x00, 0x0b, 0x49, 0x44, 0x41,
    0x54, 0x78, 0xda, 0x63, 0xfc, 0xff, 0x1f, 0x00, 0x03, 0x03,
    0x02, 0x00, 0xef, 0xbf, 0xa7, 0xdb, 0x00, 0x00, 0x00, 0x00,
    0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82};

bool ReadProtocolField(const std::string &Message, size_t &Offset,
                       std::string &OutField) {
  const size_t LengthEnd = Message.find('\n', Offset);
  if (LengthEnd == std::string::npos) {
    return false;
  }

  const std::string LengthText = Message.substr(Offset, LengthEnd - Offset);
  char *EndPtr = nullptr;
  const unsigned long FieldLength = std::strtoul(LengthText.c_str(), &EndPtr, 10);
  if (EndPtr == nullptr || *EndPtr != '\0') {
    return false;
  }

  Offset = LengthEnd + 1;
  if (Offset + FieldLength > Message.size()) {
    return false;
  }

  OutField = Message.substr(Offset, FieldLength);
  Offset += FieldLength;
  if (Offset < Message.size() && Message[Offset] == '\n') {
    ++Offset;
  }
  return true;
}

bool ParseRequest(const std::string &Message, std::string &OutReplyQueue,
                  std::string &OutCommand, std::string &OutPath) {
  constexpr const char *Header = "UMQ1\n";
  constexpr size_t HeaderLength = 5;
  if (Message.rfind(Header, 0) != 0) {
    return false;
  }

  size_t Offset = HeaderLength;
  return ReadProtocolField(Message, Offset, OutReplyQueue) &&
         ReadProtocolField(Message, Offset, OutCommand) &&
         ReadProtocolField(Message, Offset, OutPath);
}

FString DecodeUtf8(const std::string &Value) {
  return FString(UTF8_TO_TCHAR(Value.c_str()));
}

FString ValidateReadableFile(const FString &Path, const TCHAR *ExpectedExtension) {
  if (Path.IsEmpty()) {
    return TEXT("Path is empty.");
  }
  if (!FPaths::FileExists(Path)) {
    return FString::Printf(TEXT("File does not exist: %s"), *Path);
  }
  if (!FPaths::GetExtension(Path, true).Equals(ExpectedExtension,
                                               ESearchCase::IgnoreCase)) {
    return FString::Printf(TEXT("Expected %s file: %s"), ExpectedExtension, *Path);
  }
  return FString();
}

FString ValidateWritablePngPath(const FString &Path) {
  if (Path.IsEmpty()) {
    return TEXT("Path is empty.");
  }
  if (!FPaths::GetExtension(Path, true).Equals(TEXT(".png"),
                                               ESearchCase::IgnoreCase)) {
    return FString::Printf(TEXT("Expected .png output path: %s"), *Path);
  }

  const FString Directory = FPaths::GetPath(Path);
  if (!Directory.IsEmpty() &&
      !IFileManager::Get().MakeDirectory(*Directory, true)) {
    return FString::Printf(TEXT("Failed to create output directory: %s"),
                           *Directory);
  }
  return FString();
}

} // namespace

FUnrealMirrorIpcServer::FUnrealMirrorIpcServer() : bStopRequested(false) {}

FUnrealMirrorIpcServer::~FUnrealMirrorIpcServer() { Stop(); }

void FUnrealMirrorIpcServer::Start() {
  if (WorkerThread) {
    return;
  }

  bStopRequested.store(false);
  boost::interprocess::message_queue::remove(UnrealMirrorQueueName);
  boost::interprocess::message_queue(boost::interprocess::create_only,
                                     UnrealMirrorQueueName, MaxQueueMessages,
                                     MaxMessageSize);
  WorkerThread = MakeUnique<std::thread>(&FUnrealMirrorIpcServer::Run, this);

  UE_LOG(LogUnrealMirrorIpc, Display,
         TEXT("UnrealMirror IPC server started: %s"),
         *GetQueueName());
}

void FUnrealMirrorIpcServer::Stop() {
  if (!WorkerThread) {
    return;
  }

  bStopRequested.store(true);
  if (WorkerThread->joinable()) {
    WorkerThread->join();
  }
  WorkerThread.Reset();
  boost::interprocess::message_queue::remove(UnrealMirrorQueueName);

  UE_LOG(LogUnrealMirrorIpc, Display, TEXT("UnrealMirror IPC server stopped."));
}

FString FUnrealMirrorIpcServer::GetQueueName() const {
  return UTF8_TO_TCHAR(UnrealMirrorQueueName);
}

void FUnrealMirrorIpcServer::Run() {
  try {
    boost::interprocess::message_queue Queue(boost::interprocess::open_only,
                                             UnrealMirrorQueueName);
    std::vector<char> Buffer(MaxMessageSize);
    while (!bStopRequested.load()) {
      size_t ReceivedSize = 0;
      unsigned int Priority = 0;
      const boost::posix_time::ptime Deadline =
          boost::posix_time::microsec_clock::universal_time() +
          boost::posix_time::milliseconds(100);
      if (Queue.timed_receive(Buffer.data(), Buffer.size(), ReceivedSize,
                              Priority, Deadline)) {
        HandleRequest(std::string(Buffer.data(), ReceivedSize));
      }
    }
  } catch (const std::exception &Error) {
    UE_LOG(LogUnrealMirrorIpc, Error, TEXT("IPC server stopped with error: %s"),
           UTF8_TO_TCHAR(Error.what()));
  }
}

void FUnrealMirrorIpcServer::HandleRequest(const std::string &Request) {
  std::string ReplyQueueName;
  std::string Command;
  std::string PathUtf8;
  if (!ParseRequest(Request, ReplyQueueName, Command, PathUtf8)) {
    UE_LOG(LogUnrealMirrorIpc, Warning, TEXT("Ignoring malformed IPC request."));
    return;
  }

  if (Command == "shutdown") {
    const FString Message = TEXT("Shutdown requested.");
    UE_LOG(LogUnrealMirrorIpc, Display, TEXT("%s"), *Message);
    SendReply(ReplyQueueName, true, Message);
    AsyncTask(ENamedThreads::GameThread,
              []() { FPlatformMisc::RequestExit(false); });
    return;
  }

  const FString Path = DecodeUtf8(PathUtf8);
  FString Error;
  FString Message;
  bool bOk = true;

  if (Command == "load-vrm-model") {
    Error = ValidateReadableFile(Path, TEXT(".vrm"));
    bOk = Error.IsEmpty();
    Message = bOk ? FString::Printf(TEXT("VRM model path accepted: %s"), *Path)
                  : Error;
  } else if (Command == "load-vrm-animation") {
    Error = ValidateReadableFile(Path, TEXT(".vrma"));
    bOk = Error.IsEmpty();
    Message = bOk ? FString::Printf(TEXT("VRM animation path accepted: %s"),
                                    *Path)
                  : Error;
  } else if (Command == "capture-png-screenshot") {
    Error = ValidateWritablePngPath(Path);
    bOk = Error.IsEmpty();
    if (bOk) {
      TArray<uint8> PngBytes;
      PngBytes.Append(DummyPngBytes, UE_ARRAY_COUNT(DummyPngBytes));
      bOk = FFileHelper::SaveArrayToFile(PngBytes, *Path);
      Message = bOk ? FString::Printf(TEXT("Dummy PNG screenshot saved: %s"), *Path)
                    : FString::Printf(TEXT("Failed to save PNG file: %s"), *Path);
    } else {
      Message = Error;
    }
  } else {
    bOk = false;
    Message = FString::Printf(TEXT("Unknown command: %s"),
                              UTF8_TO_TCHAR(Command.c_str()));
  }

  if (bOk) {
    UE_LOG(LogUnrealMirrorIpc, Display, TEXT("%s"), *Message);
  } else {
    UE_LOG(LogUnrealMirrorIpc, Warning, TEXT("%s"), *Message);
  }
  SendReply(ReplyQueueName, bOk, Message);
}

void FUnrealMirrorIpcServer::SendReply(const std::string &ReplyQueueName,
                                       bool bOk, const FString &Message) {
  if (ReplyQueueName.empty()) {
    return;
  }

  try {
    boost::interprocess::message_queue ReplyQueue(boost::interprocess::open_only,
                                                  ReplyQueueName.c_str());
    const std::string MessageUtf8 = TCHAR_TO_UTF8(*Message);
    const std::string Reply = std::string(bOk ? "OK\n" : "ERR\n") + MessageUtf8;
    ReplyQueue.send(Reply.data(), Reply.size(), 0);
  } catch (const std::exception &Error) {
    UE_LOG(LogUnrealMirrorIpc, Warning, TEXT("Failed to send IPC reply: %s"),
           UTF8_TO_TCHAR(Error.what()));
  }
}
