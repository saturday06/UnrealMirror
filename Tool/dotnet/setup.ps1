#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.6

param(
  [string]$TargetPlatform,
  [string]$TargetConfiguration,
  [string]$TargetType
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

function Build-Prerequisite {
  param(
    [string]$TargetPlatform,
    [string]$TargetConfiguration,
    [string]$TargetType
  )

  $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
  $env:DOTNET_CLI_UI_LANGUAGE = "en"
  $env:VSLANG = "1033"

  $config = Import-PowerShellDataFile (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")
  $vsCmakeGenerator = $config.VsCmakeGenerator
  $vcVersion = $config.VcVersion
  $osxDeploymentTarget = $config.OsxDeploymentTarget
  $cmakeVersion = $config.CmakeVersion

  Write-Output "Target Platform: $TargetPlatform"
  Write-Output "Target Configuration: $TargetConfiguration"
  Write-Output "Target Type: $TargetType"

  if ($TargetType -ne "Editor" -and ($TargetConfiguration -in @("Debug", "DebugGame", "Development"))) {
    $release = $false
    $cmakeConfig = "Debug"
  }
  else {
    $release = $true
    $cmakeConfig = "Release"
  }
  Write-Output "Release: ${release}"

  Write-Output "Environment Variables:"
  Get-ChildItem Env: | Sort-Object Name | ForEach-Object {
    Write-Output "  $($_.Name)=$($_.Value)"
  }

  & {
    try {
      & (Join-Path -Path $PSScriptRoot -ChildPath "format.ps1")
    }
    catch {
      Write-Output $_
    }
  }

  $processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
  switch ($processArchitecture) {
    "X64" {
      $cmakeArchitecture = "x86_64"
      $cmakeDefaultLinuxTargetPlatform = "Linux"
    }
    "Arm64" {
      $cmakeArchitecture = "arm64"
      $cmakeDefaultLinuxTargetPlatform = "LinuxArm64"
    }
    default {
      $errorMessage = "Unsupported Process Architecture: ${processArchitecture}"
      throw $errorMessage
    }
  }

  $cmakeFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "..", "cmake"
  $cmakeDistributionPath = Join-Path -Path $cmakeFolderPath -ChildPath "distribution"
  New-Item -ItemType Directory $cmakeDistributionPath -Force | Out-Null

  if ($IsWindows) {
    $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-windows-${cmakeArchitecture}.zip"
    $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*", "bin", "cmake.exe"
    if (-not ($TargetPlatform)) {
      $TargetPlatform = "Win64"
    }
  }
  elseif ($IsMacOS) {
    $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-macos-universal.tar.gz"
    $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*", "CMake.app", "Contents", "bin", "cmake"
    if (-not ($TargetPlatform)) {
      $TargetPlatform = "Mac"
    }
  }
  elseif ($IsLinux) {
    $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-linux-${cmakeArchitecture}.tar.gz"
    $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*", "bin", "cmake"
    if (-not ($TargetPlatform)) {
      $TargetPlatform = $cmakeDefaultLinuxTargetPlatform
    }
  }
  else {
    Write-Output "Unsupported host platform: $($PSVersionTable.Platform)"
    exit 1
  }

  $cmakeGeneratorOptions = @()
  if ($TargetPlatform -eq "Android") {
    $cmakeGenerator = "Unix Makefiles"
    $assimpBuildSharedLibs = "OFF"
  }
  elseif ($TargetPlatform -eq "Win64" -and $IsWindows) {
    $cmakeGenerator = $vsCmakeGenerator
    $cmakeGeneratorOptions += @(
      # Make deterministic
      "-DCMAKE_C_FLAGS=/experimental:deterministic"
      "-DCMAKE_CXX_FLAGS=/experimental:deterministic"
      "-DCMAKE_SHARED_LINKER_FLAGS=/INCREMENTAL:NO"
    )
    $assimpBuildSharedLibs = "ON"
  }
  elseif ($TargetPlatform -eq "Mac" -and $IsMacOS) {
    $cmakeGenerator = "Xcode"
    $cmakeGeneratorOptions += @(
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}"
    )
    $assimpBuildSharedLibs = "OFF"
  }
  elseif ($TargetPlatform -eq "Linux" -and $IsLinux) {
    $cmakeGenerator = "Unix Makefiles"
    $assimpBuildSharedLibs = "OFF"
  }
  elseif ($TargetPlatform -eq "LinuxArm64" -and $IsLinux) {
    $cmakeGenerator = "Unix Makefiles"
    $assimpBuildSharedLibs = "OFF"
  }
  elseif ($TargetPlatform -eq "IOS" -and $IsMacOS) {
    $cmakeGenerator = "Xcode"
    $assimpBuildSharedLibs = "OFF"
    $iosCmakeFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "..", "ios-cmake"
    $iosCmakeToolchainPath = Join-Path -Path $iosCmakeFolderPath -ChildPath "ios.toolchain.cmake"
    if (-not (Test-Path $iosCmakeToolchainPath)) {
      git -C $iosCmakeFolderPath submodule update --init --recursive --depth 1
    }
    $cmakeGeneratorOptions += @(
      "-DCMAKE_TOOLCHAIN_FILE=${iosCmakeToolchainPath}"
      "-DPLATFORM=OS64"
    )
  }
  else {
    Write-Output "Unsupported target platform: ${TargetPlatform} for $($PSVersionTable.Platform)"
    exit 1
  }
  $cmakeGeneratorOptions += @(
    "-G"
    $cmakeGenerator
    "-DBUILD_SHARED_LIBS=${assimpBuildSharedLibs}"
    "-DCMAKE_BUILD_TYPE=${cmakeConfig}"
    "-DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF"
    "-DASSIMP_WARNINGS_AS_ERRORS=OFF"
  )

  $cmakeArchiveFileName = Split-Path -Leaf ([System.Uri]::new($cmakeUrl)).AbsolutePath
  $cmakeArchiveFilePath = Join-Path -Path $cmakeFolderPath -ChildPath $cmakeArchiveFileName
  if (-not (Test-Path $cmakeArchiveFilePath)) {
    Write-Output "Downloading ${cmakeUrl}"
    Invoke-RestMethod -Uri $cmakeUrl -OutFile $cmakeArchiveFilePath
  }
  if (-not (Get-ChildItem $cmakePathPattern)) {
    & tar -xf $cmakeArchiveFilePath -C $cmakeDistributionPath
  }

  $cmakePaths = Get-ChildItem $cmakePathPattern
  if (-not $cmakePaths) {
    $errorMessage = "Failed to setup local cmake: ${cmakePathPattern} not found"
    throw $errorMessage
  }
  $cmake = $cmakePaths[0].FullName

  Write-Output "Using CMake: $cmake"
  & $cmake --version

  $assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "..", "VRM4U", "assimp"
  if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
    git -C $assimpSourceFolderPath submodule update --init --recursive --depth 1
  }

  $assimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build", $TargetPlatform, $cmakeConfig
  $vrm4uAssimpBaseFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "..", "..", "Plugins", "VRM4U", "ThirdParty", "assimp"

  New-Item -ItemType Directory $assimpBuildFolderPath -Force | Out-Null

  if (-not (Test-Path (Join-Path -Path $assimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
    & $cmake `
      $cmakeGeneratorOptions `
      -B $assimpBuildFolderPath `
      -S $assimpSourceFolderPath
  }
  & $cmake --build $assimpBuildFolderPath --config $cmakeConfig --parallel 4

  if ($TargetPlatform -eq "Win64") {
    $vrm4uAssimpBinFolderPath = Join-Path -Path $vrm4uAssimpBaseFolderPath -ChildPath "bin", "x64"
    $vrm4uAssimpLibFolderPath = Join-Path -Path $vrm4uAssimpBaseFolderPath -ChildPath "lib", "x64", $cmakeConfig
    New-Item -ItemType Directory $vrm4uAssimpBinFolderPath -Force | Out-Null
    New-Item -ItemType Directory $vrm4uAssimpLibFolderPath -Force | Out-Null

    if ($release) {
      $cRuntime = "mt"
    }
    else {
      $cRuntime = "mtd"
    }

    $assimpDllFileName = "assimp-${vcVersion}-${cRuntime}.dll"
    $vrm4uAssimpDllPath = Join-Path -Path $vrm4uAssimpBinFolderPath -ChildPath $assimpDllFileName
    $assimpDllPath = Join-Path -Path $assimpBuildFolderPath -ChildPath "bin", $cmakeConfig, $assimpDllFileName
    if (-not (Test-Path $vrm4uAssimpDllPath) -or ((Get-FileHash $vrm4uAssimpDllPath).Hash -ne (Get-FileHash $assimpDllPath).Hash)) {
      Copy-Item $assimpDllPath $vrm4uAssimpDllPath
    }

    $assimpPdbFileName = "assimp-${vcVersion}-${cRuntime}.pdb"
    $vrm4uAssimpPdbPath = Join-Path -Path $vrm4uAssimpBinFolderPath -ChildPath $assimpPdbFileName
    $assimpPdbPath = Join-Path -Path $assimpBuildFolderPath -ChildPath "bin", $cmakeConfig, $assimpPdbFileName
    if (-not (Test-Path $vrm4uAssimpPdbPath) -or ((Get-FileHash $vrm4uAssimpPdbPath).Hash -ne (Get-FileHash $assimpPdbPath).Hash)) {
      Copy-Item $assimpPdbPath $vrm4uAssimpPdbPath
    }

    $assimpLibFileName = "assimp-${vcVersion}-${cRuntime}.lib"
    $vrm4uAssimpLibPath = Join-Path -Path $vrm4uAssimpLibFolderPath -ChildPath $assimpLibFileName
    $assimpLibPath = Join-Path -Path $assimpBuildFolderPath -ChildPath "lib", $cmakeConfig, $assimpLibFileName
    if (-not (Test-Path $vrm4uAssimpLibPath) -or ((Get-FileHash $vrm4uAssimpLibPath).Hash -ne (Get-FileHash $assimpLibPath).Hash)) {
      Copy-Item $assimpLibPath $vrm4uAssimpLibPath
    }
  }
  else {
    if ($release) {
      $debugPostfix = ""
    }
    else {
      $debugPostfix = "d"
    }
    if ($TargetPlatform -in @("IOS", "Mac")) {
      $assimpLibPath = Join-Path -Path $assimpBuildFolderPath -ChildPath "lib", $cmakeConfig, "libassimp${debugPostfix}.a"
    }
    else {
      $assimpLibPath = Join-Path -Path $assimpBuildFolderPath -ChildPath "lib", "libassimp${debugPostfix}.a"
    }
    $vrm4uAssimpLibFolderPath = Join-Path -Path $vrm4uAssimpBaseFolderPath -ChildPath "lib", $TargetPlatform
    New-Item -ItemType Directory $vrm4uAssimpLibFolderPath -Force | Out-Null
    Copy-Item $assimpLibPath (Join-Path -Path $vrm4uAssimpLibFolderPath -ChildPath "libassimp.a")
  }

  $vrm4uAssimpIncludeFolderPath = Join-Path -Path $vrm4uAssimpBaseFolderPath -ChildPath "include", "assimp"
  Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force | Out-Null
  New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force | Out-Null
  Copy-Item (Join-Path -Path $assimpSourceFolderPath -ChildPath "include", "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
  Copy-Item (Join-Path -Path $assimpBuildFolderPath -ChildPath "include", "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
}

$buildPrerequisitesMutex = [System.Threading.Mutex]::new($false, "UnrealMirror.BuildPrerequisites:${PSScriptRoot}")
$buildPrerequisitesMutex.WaitOne([System.Threading.Timeout]::Infinite)
try {
  Build-Prerequisite `
    -TargetPlatform $TargetPlatform `
    -TargetConfiguration $TargetConfiguration `
    -TargetType $TargetType
}
finally {
  $buildPrerequisitesMutex.Dispose()
}
