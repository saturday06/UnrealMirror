#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4

param(
  [string]$TargetPlatform,
  [string]$TargetConfiguration
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$config = Import-PowerShellDataFile (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")
$vsCmakeGenerator = $config.VsCmakeGenerator
$vcVersion = $config.VcVersion
$osxDeploymentTarget = $config.OsxDeploymentTarget
$cmakeVersion = $config.CmakeVersion

Write-Output "Target Platform: $TargetPlatform"
Write-Output "Target Configuration: $TargetConfiguration"

$preferReleaseSetup = $true
if ($TargetConfiguration -in @(
    "Debug",
    "Debug Editor",
    "DebugGame",
    "DebugGame Editor",
    "Development",
    "Development Editor"
  )) {
  $preferReleaseSetup = $false
}
Write-Output "Prefer Release Setup: $preferReleaseSetup"

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

$cmakeFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "cmake"
$cmakeDistributionPath = Join-Path -Path $cmakeFolderPath -ChildPath "distribution"
New-Item -ItemType Directory $cmakeDistributionPath -Force

if ($IsWindows) {
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-windows-${cmakeArchitecture}.zip"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "bin", "cmake.exe"
  if (-not ($TargetPlatform)) {
    $TargetPlatform = "Win64"
  }
}
elseif ($IsMacOS) {
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-macos-universal.tar.gz"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "CMake.app", "Contents", "bin", "cmake"
  if (-not ($TargetPlatform)) {
    $TargetPlatform = "Mac"
  }
}
elseif ($IsLinux) {
  $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v${cmakeVersion}/cmake-${cmakeVersion}-linux-${cmakeArchitecture}.tar.gz"
  $cmakePathPattern = Join-Path -Path $cmakeDistributionPath -ChildPath "*" -AdditionalChildPath "bin", "cmake"
  if (-not ($TargetPlatform)) {
    $TargetPlatform = $cmakeDefaultLinuxTargetPlatform
  }
}
else {
  Write-Output "Unsupported host platform: $($PSVersionTable.Platform)"
  exit 1
}

$cmakeBaseOptions = @()
if ($TargetPlatform -eq "Android") {
  $cmakeGenerator = "Unix Makefiles"
  $cmakeCflags = ""
  $cmakeCxxflags = ""
  $assimpBuildSharedLibs = "OFF"
}
elseif ($TargetPlatform -eq "Win64" -and $IsWindows) {
  $cmakeGenerator = $vsCmakeGenerator
  $cmakeCflags = "/utf-8"
  $cmakeCxxflags = "/utf-8"
  $assimpBuildSharedLibs = "ON"
}
elseif ($TargetPlatform -eq "Mac" -and $IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmakeCflags = ""
  $cmakeCxxflags = ""
  $cmakeBaseOptions += @(
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}"
  )
  $assimpBuildSharedLibs = "OFF"
}
elseif ($TargetPlatform -eq "Linux" -and $IsLinux) {
  $cmakeGenerator = "Unix Makefiles"
  $cmakeCflags = ""
  $cmakeCxxflags = ""
  $assimpBuildSharedLibs = "OFF"
}
elseif ($TargetPlatform -eq "LinuxArm64" -and $IsLinux) {
  $cmakeGenerator = "Unix Makefiles"
  $cmakeCflags = ""
  $cmakeCxxflags = ""
  $assimpBuildSharedLibs = "OFF"
}
elseif ($TargetPlatform -eq "IOS" -and $IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmakeCflags = ""
  $cmakeCxxflags = ""
  $assimpBuildSharedLibs = "OFF"
}
else {
  Write-Output "Unsupported target platform: ${TargetPlatform} for $($PSVersionTable.Platform)"
  exit 1
}
$cmakeBaseOptions += @(
  "-G", $cmakeGenerator,
  "-DCMAKE_C_FLAGS=${cmakeCflags}",
  "-DCMAKE_CXX_FLAGS=${cmakeCxxflags}"
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

$grpcFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "grpc"
New-Item -ItemType Directory $grpcFolderPath -Force
if (-not (Test-Path (Join-Path -Path $grpcFolderPath -ChildPath ".git"))) {
  git -C $grpcFolderPath init
}
try {
  git -C $grpcFolderPath remote add origin https://github.com/grpc/grpc
}
catch [System.Management.Automation.NativeCommandExitException] {
  Write-Output "Already added"
}
$grpcGitTag = "v${grpcVersion}"
try {
  git -C $grpcFolderPath rev-parse $grpcGitTag --
}
catch [System.Management.Automation.NativeCommandExitException] {
  git -C $grpcFolderPath fetch --depth 1 origin "refs/tags/${grpcGitTag}:refs/tags/${grpcGitTag}"
}
git -C $grpcFolderPath reset --hard $grpcGitTag
git -C $grpcFolderPath submodule update --init --recursive --depth 1

$grpcBuildFolderPath = Join-Path -Path $grpcFolderPath -ChildPath ".build"
New-Item -ItemType Directory $grpcBuildFolderPath -Force
if (-not (Test-Path (Join-Path -Path $grpcBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  $grpcInstallPrefixPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "ThirdParty", "grpc"
  & $cmake `
    $cmakeBaseOptions `
    -DgRPC_INSTALL=ON `
    -DCMAKE_CXX_STANDARD=17 `
    "-DCMAKE_INSTALL_PREFIX=${grpcInstallPrefixPath}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $grpcBuildFolderPath `
    -S $grpcFolderPath
}

& $cmake --build $grpcBuildFolderPath --config Release --target install --parallel 4

$assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "VRM4U" -AdditionalChildPath "assimp"
if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
  git -C $assimpSourceFolderPath submodule update --init --recursive --depth 1
}

$debugAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$vrm4uAssimpFolderPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "Plugins", "VRM4U", "ThirdParty", "assimp"
$macStaticLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimp.a"

New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release") -Force

if (-not (Test-Path (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    $cmakeBaseOptions `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${assimpBuildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Debug `
    -B $debugAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $debugAssimpBuildFolderPath --config Debug --parallel 4
if ($TargetPlatform -eq "Win64") {
  $debugDllPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mtd.dll"
  if (-not (Test-Path $debugDllPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.dll") $debugDllPath
  }
  $debugPdbPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mtd.pdb"
  if (-not (Test-Path $debugPdbPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.pdb") $debugPdbPath
  }
  $debugLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug", "assimp-${vcVersion}-mtd.lib"
  if (-not(Test-Path $debugLibPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "assimp-${vcVersion}-mtd.lib") $debugLibPath
  }
}
elseif ($TargetPlatform -eq "Mac") {
  if (-not ($preferReleaseSetup)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "libassimpd.a") $macStaticLibPath
  }
}
else {
  Write-Output "Debug build is not supported on this platform: $($PSVersionTable.Platform)"
}

if (-not (Test-Path (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    $cmakeBaseOptions `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${assimpBuildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $releaseAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $releaseAssimpBuildFolderPath --config Release --parallel 4

if ($TargetPlatform -eq "Win64") {
  $releaseDllPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mt.dll"
  if (-not (Test-Path $releaseDllPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.dll") $releaseDllPath
  }
  $releasePdbPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64", "assimp-${vcVersion}-mt.pdb"
  if (-not (Test-Path $releasePdbPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.pdb") $releasePdbPath
  }
  $releaseLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release", "assimp-${vcVersion}-mt.lib"
  if (-not (Test-Path $releaseLibPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.lib") $releaseLibPath
  }
}
elseif ($TargetPlatform -eq "Mac") {
  if ($preferReleaseSetup) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "libassimp.a") $macStaticLibPath
  }
}
else {
  Write-Output "Release build is not supported on this platform: $($PSVersionTable.Platform)"
}

$vrm4uAssimpIncludeFolderPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "include" -AdditionalChildPath "assimp"
Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force
New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force
Copy-Item (Join-Path -Path $assimpSourceFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
if ($preferReleaseSetup) {
  $preferedAssimpBuildFolderPath = $releaseAssimpBuildFolderPath
}
else {
  $preferedAssimpBuildFolderPath = $debugAssimpBuildFolderPath
}
Copy-Item (Join-Path -Path $preferedAssimpBuildFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
