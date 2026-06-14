#!/bin/sh

set -eu

cd "$(dirname "$0")/dotnet"

./ue-dotnet.sh tool restore
./ue-dotnet.sh tool run pwsh -- format.ps1
