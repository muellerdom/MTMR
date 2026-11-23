#!/bin/sh
# Builds a universal (arm64 + x86_64), ad-hoc signed MTMR.app into Release/.
set -e
cd "$(dirname "$0")"

xcodebuild -project MTMR.xcodeproj -scheme MTMR -configuration Release \
	-derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

rm -rf Release/MTMR.app
mkdir -p Release
cp -R build/Build/Products/Release/MTMR.app Release/
echo "Built Release/MTMR.app"
