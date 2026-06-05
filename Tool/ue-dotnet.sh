#!/usr/bin/env bash

set -eu -o pipefail

cd "$(dirname "$0")"

engine_association=$(
  python3 - <<ENGINE_ASSOCIATION
import json
import pathlib
uproject_path = pathlib.Path("../UnrealMirror.uproject")
uproject = json.loads(uproject_path.read_text())
print(uproject['EngineAssociation'])
ENGINE_ASSOCIATION
)

uname_system=$(uname -s)

case "$uname_system" in
Darwin)
  if [ -z "${UE_ROOT:-}" ]; then
    UE_ROOT="/Users/Shared/Epic Games/UE_${engine_association}"
  fi
  batch_files_platform_path="${UE_ROOT}/Engine/Build/BatchFiles/Mac"
  ;;
Linux)
  if [ -z "${UE_ROOT:-}" ]; then
    echo 'Please set the "UE_ROOT" environment variable' >&2
    exit 1
  fi
  batch_files_platform_path="${UE_ROOT}/Engine/Build/BatchFiles/Linux"
  ;;
*)
  echo "Unsupported platform: ${uname_system}" >&2
  exit 1
  ;;
esac

set +eu
# shellcheck disable=SC1091
. "${batch_files_platform_path}/SetupEnvironment.sh" -dotnet "$batch_files_platform_path"
set -eu

exec dotnet "$@"
