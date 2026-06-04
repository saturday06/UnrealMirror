// Copyright Epic Games, Inc. All Rights Reserved.

#include "UnrealMirror.h"

#include "UnrealMirrorIpcServer.h"

void FUnrealMirrorModule::StartupModule() {
  FDefaultGameModuleImpl::StartupModule();
  IpcServer = MakeUnique<FUnrealMirrorIpcServer>();
  IpcServer->Start();
}

void FUnrealMirrorModule::ShutdownModule() {
  if (IpcServer) {
    IpcServer->Stop();
    IpcServer.Reset();
  }
  FDefaultGameModuleImpl::ShutdownModule();
}

IMPLEMENT_PRIMARY_GAME_MODULE(FUnrealMirrorModule, UnrealMirror, "UnrealMirror");
