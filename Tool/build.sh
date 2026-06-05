#!/bin/sh

set -eu

cd "$(dirname "$0")"

./ue-dotnet.sh tool restore
./ue-dotnet.sh tool run pwsh -- format.ps1
./ue-dotnet.sh tool run pwsh -- uat-build-cook-run.ps1 "$@"
