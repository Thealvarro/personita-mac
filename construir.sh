#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Compila Personita y arma build/Personita.app firmada ad-hoc.
set -e
cd "$(dirname "$0")"
APP=build/Personita.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Fuentes/*.swift -o "$APP/Contents/MacOS/Personita"
cp Info.plist "$APP/Contents/Info.plist"
codesign -f -s - "$APP"
echo "Listo: $APP"
