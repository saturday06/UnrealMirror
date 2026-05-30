#!/usr/bin/env pwsh
# SPDX-License-Identifier: Apache-2.0
#Requires -Version 7.4
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3

$cmake = "cmake"
if ($IsWindows) {
  $cmakeGenerator = "Visual Studio 17 2022"
  $vsVersionRange = "[17.0,18.0)"
  $vcVersion = "vc143"

  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
  }
  $vsInstallationPath = & $vswhere -version $vsVersionRange -property installationPath
  if (-not $vsInstallationPath) {
    throw "Visual Studio was not found"
  }
  $cmake = Join-Path $vsInstallationPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
elseif ($IsMacOS) {
  $cmakeGenerator = "Xcode"
  $cmake = Get-Command cmake
}
else {
  $cmakeGenerator = "Unix Makefiles"
  $cmake = Get-Command cmake
}

if (-not (Test-Path $cmake)) {
  throw "cmake.exe was not found: $cmake"
}

$assimpSourceFolderPath = Join-Path $PSScriptRoot "assimp"
if (-not (Test-Path (Join-Path $assimpSourceFolderPath "Readme.md"))) {
  git -C $PSScriptRoot submodule update --init --recursive
}

$debugAssimpBuildFolderPath = Join-Path $assimpSourceFolderPath "build" "Debug"
New-Item -ItemType Directory $debugAssimpBuildFolderPath -Force

$releaseAssimpBuildFolderPath = Join-Path $assimpSourceFolderPath "build" "Release"
New-Item -ItemType Directory $releaseAssimpBuildFolderPath -Force

$buildSharedLibs = $IsWindows ? "ON" : "OFF"
$vrm4uAssimpFolderPath = Join-Path $PSScriptRoot ".." ".." "Plugins" "VRM4U" "ThirdParty" "assimp"

New-Item -ItemType Directory (Join-Path $vrm4uAssimpFolderPath "bin" "x64") -Force
New-Item -ItemType Directory (Join-Path $vrm4uAssimpFolderPath "lib" "x64" "Debug") -Force
New-Item -ItemType Directory (Join-Path $vrm4uAssimpFolderPath "lib" "x64" "Release") -Force

if (-not (Test-Path (Join-Path $debugAssimpBuildFolderPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Debug `
    -B $debugAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $debugAssimpBuildFolderPath --config Debug
if ($IsWindows) {
  Copy-Item (Join-Path $debugAssimpBuildFolderPath "bin" "Debug" "assimp-${vcVersion}-mtd.dll") (Join-Path $vrm4uAssimpFolderPath "bin" "x64")
  Copy-Item (Join-Path $debugAssimpBuildFolderPath "bin" "Debug" "assimp-${vcVersion}-mtd.pdb") (Join-Path $vrm4uAssimpFolderPath "bin" "x64")
  Copy-Item (Join-Path $debugAssimpBuildFolderPath "lib" "Debug" "assimp-${vcVersion}-mtd.lib") (Join-Path $vrm4uAssimpFolderPath "lib" "x64" "Debug")
}
elseif ($IsMacOS) {
  Copy-Item (Join-Path $debugAssimpBuildFolderPath "lib" "libassimpd.a") (Join-Path $vrm4uAssimpFolderPath "lib" "Mac" "libassimpd.a")
}

if (-not (Test-Path (Join-Path $releaseAssimpBuildFolderPath "CMakeCache.txt"))) {
  & $cmake `
    -G $cmakeGenerator `
    -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF `
    -DASSIMP_WARNINGS_AS_ERRORS=OFF `
    "-DBUILD_SHARED_LIBS=${buildSharedLibs}" `
    -DCMAKE_BUILD_TYPE=Release `
    -B $releaseAssimpBuildFolderPath `
    -S $assimpSourceFolderPath
}
& $cmake --build $releaseAssimpBuildFolderPath --config Release

if ($IsWindows) {
  Copy-Item (Join-Path $releaseAssimpBuildFolderPath "bin" "Release" "assimp-${vcVersion}-mt.dll") (Join-Path $vrm4uAssimpFolderPath "bin" "x64")
  Copy-Item (Join-Path $releaseAssimpBuildFolderPath "bin" "Release" "assimp-${vcVersion}-mt.pdb") (Join-Path $vrm4uAssimpFolderPath "bin" "x64")
  Copy-Item (Join-Path $releaseAssimpBuildFolderPath "lib" "Release" "assimp-${vcVersion}-mt.lib") (Join-Path $vrm4uAssimpFolderPath "lib" "x64" "Release")
}
elseif ($IsMacOS) {
  Copy-Item (Join-Path $releaseAssimpBuildFolderPath "lib" "libassimp.a") (Join-Path $vrm4uAssimpFolderPath "lib" "Mac" "libassimp.a")
}

$vrm4uAssimpIncludeFolderPath = Join-Path $vrm4uAssimpFolderPath "include" "assimp"
Remove-Item $vrm4uAssimpIncludeFolderPath -Recurse -Force
New-Item -ItemType Directory -Path $vrm4uAssimpIncludeFolderPath -Force
Copy-Item (Join-Path $assimpSourceFolderPath "include" "assimp" "*") $vrm4uAssimpIncludeFolderPath -Recurse
Copy-Item (Join-Path $releaseAssimpBuildFolderPath "include" "assimp" "*") $vrm4uAssimpIncludeFolderPath -Recurse
