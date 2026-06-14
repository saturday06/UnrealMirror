// VRM4U Copyright (c) 2021-2026 Haruyoshi Yamamoto. This software is released
// under the MIT License. Copyright 1998-2018 Epic Games, Inc. All Rights
// Reserved. ApplicationLifecycleComponent.cpp: Component to handle receiving
// notifications from the OS about application state (activated, suspended,
// termination, etc)

#include "LoadVrmPath.h"

#include "HAL/PlatformMisc.h"
#include "Misc/CoreDelegates.h"
#include "Misc/Paths.h"

#if PLATFORM_WINDOWS
#include "Windows/AllowWindowsPlatformTypes.h"
#include "Windows/HideWindowsPlatformTypes.h"
#include "commdlg.h"
#endif

ULoadVrmPathComponent::FStaticOnDropFiles
    ULoadVrmPathComponent::StaticOnDropFilesDelegate;
ULoadVrmPathComponent *ULoadVrmPathComponent::s_LatestActiveComponent = nullptr;

ULoadVrmPathComponent::ULoadVrmPathComponent(
    const FObjectInitializer &ObjectInitializer)
    : Super(ObjectInitializer) {}

void ULoadVrmPathComponent::OnRegister() {
  Super::OnRegister();

  StaticOnDropFilesDelegate.AddUObject(
      this, &ULoadVrmPathComponent::OnDropFilesDelegate_Handler);

  s_LatestActiveComponent = this;
}

void ULoadVrmPathComponent::OnUnregister() {
  Super::OnUnregister();

  StaticOnDropFilesDelegate.RemoveAll(this);

  if (s_LatestActiveComponent == this) {
    s_LatestActiveComponent = nullptr;
  }
}

bool ULoadVrmPathComponent::VRMGetOpenFileName(FString &FileName) {
  FileName = "";

  const FString EnvFileName =
      FPlatformMisc::GetEnvironmentVariable(TEXT("UNREAL_MIRROR_VRM_PATH"));
  if (EnvFileName.IsEmpty() == false) {
    FileName = EnvFileName;
    if (FPaths::FileExists(FileName) == false) {
      UE_LOG(LogTemp, Warning,
             TEXT("UNREAL_MIRROR_VRM_PATH does not exist: %s"), *FileName);
      return false;
    }
    return true;
  }

#if PLATFORM_WINDOWS
  {
    OPENFILENAME ofn = {};
    TCHAR filename[MAX_PATH] = {};

    filename[0] = '\0';
    ofn.lStructSize = sizeof(OPENFILENAME);
    ofn.lpstrFilter =
        TEXT("VRM file(*.vrm)\0*.vrm\0") TEXT("all file(*.*)\0*.*\0\0");
    ofn.lpstrFile = filename;
    ofn.nMaxFile = sizeof(filename);
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrTitle = TEXT("Model");

    if (GetOpenFileName(&ofn)) {
      FileName = filename;
      return true;
    }
  }
#endif
  return false;
}
