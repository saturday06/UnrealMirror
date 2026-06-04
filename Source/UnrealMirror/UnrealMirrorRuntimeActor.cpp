// Copyright Epic Games, Inc. All Rights Reserved.

#include "UnrealMirrorRuntimeActor.h"

#include "Async/Async.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/SceneCaptureComponent2D.h"
#include "Components/SceneComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/SkyLightComponent.h"
#include "Engine/TextureRenderTarget2D.h"
#include "ImageUtils.h"
#include "LoaderBPFunctionLibrary.h"
#include "Misc/FileHelper.h"
#include "UnrealClient.h"
#include "VrmAssetListObject.h"

DEFINE_LOG_CATEGORY_STATIC(LogUnrealMirrorRuntime, Log, All);

namespace {

constexpr int32 CaptureWidth = 256;
constexpr int32 CaptureHeight = 256;

} // namespace

AUnrealMirrorRuntimeActor::AUnrealMirrorRuntimeActor() {
  PrimaryActorTick.bCanEverTick = false;

  SceneRoot = CreateDefaultSubobject<USceneComponent>(TEXT("SceneRoot"));
  RootComponent = SceneRoot;

  MeshComponent =
      CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("VRMModel"));
  MeshComponent->SetupAttachment(SceneRoot);
  MeshComponent->SetRelativeLocation(FVector::ZeroVector);
  MeshComponent->SetRelativeRotation(FRotator::ZeroRotator);
  MeshComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
  MeshComponent->bCastDynamicShadow = true;

  CaptureComponent =
      CreateDefaultSubobject<USceneCaptureComponent2D>(TEXT("SceneCapture"));
  CaptureComponent->SetupAttachment(SceneRoot);
  CaptureComponent->bCaptureEveryFrame = false;
  CaptureComponent->bCaptureOnMovement = false;
  CaptureComponent->FOVAngle = 35.0f;
  CaptureComponent->PrimitiveRenderMode =
      ESceneCapturePrimitiveRenderMode::PRM_RenderScenePrimitives;
  CaptureComponent->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;

  KeyLightComponent =
      CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("KeyLight"));
  KeyLightComponent->SetupAttachment(SceneRoot);
  KeyLightComponent->SetIntensity(18.0f);
  KeyLightComponent->SetRelativeRotation(FRotator(-35.0f, -30.0f, 0.0f));

  FillLightComponent =
      CreateDefaultSubobject<UPointLightComponent>(TEXT("FillLight"));
  FillLightComponent->SetupAttachment(SceneRoot);
  FillLightComponent->SetIntensity(8000.0f);
  FillLightComponent->SetAttenuationRadius(900.0f);
  FillLightComponent->SetRelativeLocation(FVector(-160.0f, -220.0f, 220.0f));

  SkyLightComponent =
      CreateDefaultSubobject<USkyLightComponent>(TEXT("SkyLight"));
  SkyLightComponent->SetupAttachment(SceneRoot);
  SkyLightComponent->SetIntensity(3.5f);
}

bool AUnrealMirrorRuntimeActor::LoadVrmModel(const FString &Path,
                                             FString &OutMessage) {
  FImportOptionData ImportOptions;
  ImportOptions.init();
  ImportOptions.MaterialType = EVRMImportMaterialType::VRMIMT_MToon;

  UVrmAssetListObject *LoadTemplate = NewObject<UVrmAssetListObject>(this);
  UVrmAssetListObject *LoadedAsset = nullptr;
  const bool bLoaded = ULoaderBPFunctionLibrary::LoadVRMFile(
      LoadTemplate, LoadedAsset, Path, ImportOptions);

  if (!bLoaded || LoadedAsset == nullptr ||
      LoadedAsset->SkeletalMesh == nullptr) {
    OutMessage = FString::Printf(TEXT("Failed to load VRM model: %s"), *Path);
    return false;
  }

  VrmAsset = LoadedAsset;
  MeshComponent->SetSkeletalMesh(LoadedAsset->SkeletalMesh, true);
  MeshComponent->SetVisibility(true, true);
  MeshComponent->RefreshBoneTransforms();
  FrameLoadedModel();
  EnsureRenderTarget();
  CaptureComponent->CaptureScene();

  OutMessage = FString::Printf(TEXT("VRM model loaded: %s"), *Path);
  UE_LOG(LogUnrealMirrorRuntime, Display, TEXT("%s"), *OutMessage);
  return true;
}

bool AUnrealMirrorRuntimeActor::LoadVrmAnimation(const FString &Path,
                                                 FString &OutMessage) {
  OutMessage = FString::Printf(TEXT("VRM animation path accepted: %s"), *Path);
  UE_LOG(LogUnrealMirrorRuntime, Display, TEXT("%s"), *OutMessage);
  return true;
}

bool AUnrealMirrorRuntimeActor::CapturePngScreenshot(const FString &Path,
                                                     FString &OutMessage) {
  if (VrmAsset == nullptr || MeshComponent->GetSkeletalMeshAsset() == nullptr) {
    OutMessage = TEXT("No VRM model has been loaded.");
    return false;
  }

  EnsureRenderTarget();
  CaptureComponent->CaptureScene();
  return WriteRenderTargetPng(Path, OutMessage);
}

void AUnrealMirrorRuntimeActor::CapturePngScreenshotAsync(
    const FString &Path, TFunction<void(bool, FString)> Completion) {
  if (VrmAsset == nullptr || MeshComponent->GetSkeletalMeshAsset() == nullptr) {
    Completion(false, TEXT("No VRM model has been loaded."));
    return;
  }

  UWorld *World = GetWorld();
  if (World == nullptr) {
    Completion(false, TEXT("Failed to find game world."));
    return;
  }

  EnsureRenderTarget();
  CaptureComponent->CaptureScene();
  UE_LOG(LogUnrealMirrorRuntime, Display,
         TEXT("PNG screenshot capture requested: %s"), *Path);
  TWeakObjectPtr<AUnrealMirrorRuntimeActor> WeakThis(this);
  Async(EAsyncExecution::ThreadPool,
        [WeakThis, Path, Completion = MoveTemp(Completion)]() mutable {
          FPlatformProcess::Sleep(0.1f);
          AsyncTask(
              ENamedThreads::GameThread,
              [WeakThis, Path, Completion = MoveTemp(Completion)]() mutable {
                AUnrealMirrorRuntimeActor *Actor = WeakThis.Get();
                if (Actor == nullptr) {
                  Completion(false,
                             TEXT("Runtime actor is no longer available."));
                  return;
                }
                FString Message;
                UE_LOG(LogUnrealMirrorRuntime, Display,
                       TEXT("PNG screenshot readback started: %s"), *Path);
                const bool bOk = Actor->WriteRenderTargetPng(Path, Message);
                Completion(bOk, Message);
              });
        });
}

bool AUnrealMirrorRuntimeActor::WriteRenderTargetPng(const FString &Path,
                                                     FString &OutMessage) {
  FTextureRenderTargetResource *RenderTargetResource =
      RenderTarget->GameThread_GetRenderTargetResource();
  if (RenderTargetResource == nullptr) {
    OutMessage = TEXT("Failed to get render target resource.");
    return false;
  }

  TArray<FColor> Pixels;
  FReadSurfaceDataFlags ReadFlags(RCM_UNorm);
  ReadFlags.SetLinearToGamma(true);
  if (!RenderTargetResource->ReadPixels(Pixels, ReadFlags) ||
      Pixels.Num() != CaptureWidth * CaptureHeight) {
    OutMessage = FString::Printf(
        TEXT("Failed to read render target pixels: %d"), Pixels.Num());
    return false;
  }

  TArray64<uint8> PngBytes;
  FImageUtils::PNGCompressImageArray(
      CaptureWidth, CaptureHeight,
      TArrayView64<const FColor>(Pixels.GetData(), Pixels.Num()), PngBytes);
  if (PngBytes.IsEmpty()) {
    OutMessage = TEXT("Failed to encode PNG screenshot.");
    return false;
  }

  if (!FFileHelper::SaveArrayToFile(PngBytes, *Path)) {
    OutMessage = FString::Printf(TEXT("Failed to save PNG file: %s"), *Path);
    return false;
  }

  OutMessage = FString::Printf(TEXT("PNG screenshot saved: %s"), *Path);
  UE_LOG(LogUnrealMirrorRuntime, Display, TEXT("%s"), *OutMessage);
  return true;
}

void AUnrealMirrorRuntimeActor::FrameLoadedModel() {
  const FBoxSphereBounds Bounds = MeshComponent->Bounds;
  const FVector Center = Bounds.Origin;
  const float Radius = FMath::Max(Bounds.SphereRadius, 50.0f);

  const FVector CameraLocation =
      Center + FVector(-Radius * 2.2f, Radius * 3.2f, Radius * 1.2f);
  CaptureComponent->SetWorldLocation(CameraLocation);
  CaptureComponent->SetWorldRotation((Center - CameraLocation).Rotation());
  CaptureComponent->OrthoWidth = Radius * 2.5f;
}

void AUnrealMirrorRuntimeActor::EnsureRenderTarget() {
  if (RenderTarget == nullptr) {
    RenderTarget = NewObject<UTextureRenderTarget2D>(this);
    RenderTarget->ClearColor = FLinearColor(0.18f, 0.18f, 0.2f, 1.0f);
    RenderTarget->RenderTargetFormat = RTF_RGBA8;
    RenderTarget->InitAutoFormat(CaptureWidth, CaptureHeight);
    RenderTarget->UpdateResourceImmediate(true);
    CaptureComponent->TextureTarget = RenderTarget;
  }
}
