// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"

#include <atomic>
#include <string>
#include <thread>

class FUnrealMirrorIpcServer {
public:
  FUnrealMirrorIpcServer();
  ~FUnrealMirrorIpcServer();

  void Start();
  void Stop();

  FString GetQueueName() const;

private:
  void Run();
  void HandleRequest(const std::string &Request);
  void SendReply(const std::string &ReplyQueueName, bool bOk,
                 const FString &Message);

  std::atomic_bool bStopRequested;
  TUniquePtr<std::thread> WorkerThread;
  TWeakObjectPtr<class AUnrealMirrorRuntimeActor> RuntimeActor;
};
