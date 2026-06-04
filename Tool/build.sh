#!/bin/sh

set -eu

cd "$(dirname "$0")"

./ue-dotnet.sh tool restore
./ue-dotnet.sh tool run pwsh -- format.ps1
./ue-dotnet.sh tool run pwsh -- build.ps1
