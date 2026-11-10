#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Desinstala Personita Mac: cierra la app, quita solo sus hooks de ~/.claude/settings.json
# y borra la app y la carpeta de avisos. Se puede correr las veces que quieras.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Personita.app"
CARPETA="$HOME/.claude/personita-mac"

pkill -f "$APP/Contents/MacOS/Personita" || true

echo "Quitando los hooks de Personita de ~/.claude/settings.json"
/usr/bin/python3 hooks/ajustes.py desinstalar

rm -rf "$APP" "$CARPETA"

echo "Listo. Personita quedó desinstalada; el resto de tu configuración no se tocó."
