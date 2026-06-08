// Copyright Epic Games, Inc. All Rights Reserved.

#include "UnrealMirror.h"

void FUnrealMirrorModule::StartupModule() {
  FDefaultGameModuleImpl::StartupModule();
}

void FUnrealMirrorModule::ShutdownModule() {
  FDefaultGameModuleImpl::ShutdownModule();
}

IMPLEMENT_PRIMARY_GAME_MODULE(FUnrealMirrorModule, UnrealMirror,
                              "UnrealMirror");
