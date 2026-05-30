#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$vsCmakeGenerator = "Visual Studio 17 2022"
$vsVersionRange = "[17.0,18.0)"
$vcVersion = "vc143"
$osxDeploymentTarget = "14.0"

$cmake = "cmake"
if ($IsWindows) {
  $cmakeGenerator = $vsCmakeGenerator
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallationPath = & $vswhere -version $vsVersionRange -property installationPath
  if (-not $vsInstallationPath) {
    throw "Visual Studio was not found"
  }
  $cmake = Join-Path -Path $vsInstallationPath -ChildPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
elseif ($IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmake = (Get-Command cmake).Source
}
else {
  $cmakeGenerator = "Unix Makefiles"
  $cmake = (Get-Command cmake).Source
}

if (-not (Test-Path $cmake)) {
  throw "cmake.exe was not found: $cmake"
}

$assimpSourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "assimp"
if (-not (Test-Path (Join-Path -Path $assimpSourceFolderPath -ChildPath "Readme.md"))) {
  git -C $PSScriptRoot submodule update --init --recursive
}

$debugAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path -Path $assimpSourceFolderPath -ChildPath "build" -AdditionalChildPath "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$buildSharedLibs = $IsWindows ? "ON" : "OFF"
$vrm4uAssimpFolderPath = Join-Path -Path $PSScriptRoot -ChildPath ".." -AdditionalChildPath "..", "Plugins", "VRM4U", "ThirdParty", "assimp"

New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Debug") -Force
New-Item -ItemType Directory (Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release") -Force

if (-not (Test-Path (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}" `
    -DCMAKE_BUILD_TYPE=Debug `
    -B $debugAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $debugAssimpBuildFolderPath --config Debug
if ($IsWindows) {
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
elseif ($IsMacOS) {
  $debugStaticLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimpd.a"
  if (-not ($debugStaticLibPath)) {
    Copy-Item (Join-Path -Path $debugAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Debug", "libassimpd.a") $debugStaticLibPath
  }
}

if (-not (Test-Path (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${osxDeploymentTarget}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $releaseAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $releaseAssimpBuildFolderPath --config Release

if ($IsWindows) {
  $releaseDllPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64"
  if (-not (Test-Path $releaseDllPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.dll") $releaseDllPath
  }
  $releasePdbPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "bin" -AdditionalChildPath "x64"
  if (-not (Test-Path $releasePdbPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "bin" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.pdb") $releasePdbPath
  }
  $releaseLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "x64", "Release"
  if (-not (Test-Path $releaseLibPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "assimp-${vcVersion}-mt.lib") $releaseLibPath
  }
}
elseif ($IsMacOS) {
  $releaseStaticLibPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "lib" -AdditionalChildPath "Mac", "libassimp.a"
  if (-not (Test-Path $releaseStaticLibPath)) {
    Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "lib" -AdditionalChildPath "Release", "libassimp.a") $releaseStaticLibPath
  }
}

$vrm4uAssimpIncludeFolderPath = Join-Path -Path $vrm4uAssimpFolderPath -ChildPath "include" -AdditionalChildPath "assimp"
Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force
New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force
Copy-Item (Join-Path -Path $assimpSourceFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
Copy-Item (Join-Path -Path $releaseAssimpBuildFolderPath -ChildPath "include" -AdditionalChildPath "assimp", "*") $vrm4uAssimpIncludeFolderPath -Recurse -Force
