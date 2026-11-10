#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Compila y corre las pruebas de lógica en una carpeta temporal (por defecto, una nueva con mktemp).
set -e
cd "$(dirname "$0")/.."
DIR=${1:-$(mktemp -d)}
mkdir -p "$DIR"
swiftc -swift-version 5 -target arm64-apple-macos13.0 Fuentes/Avisos.swift Fuentes/AbrirSesion.swift Fuentes/Receptor.swift Fuentes/Emisor.swift Fuentes/NoLeidas.swift Pruebas/main.swift -o "$DIR/Pruebas"
"$DIR/Pruebas" "$DIR"
