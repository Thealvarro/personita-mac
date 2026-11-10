#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Instala Personita Mac para el usuario actual: compila la app, copia el script de avisos
# y agrega los hooks a ~/.claude/settings.json sin tocar los que ya tengas.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Personita.app"
CARPETA="$HOME/.claude/personita-mac"

falta() { echo "Falta: $1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || falta "Personita solo funciona en macOS."
[ "$(uname -m)" = "arm64" ] || falta "por ahora Personita se compila solo para Mac con chip Apple (arm64)."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || falta "macOS 13 o superior."
xcrun --find swiftc >/dev/null 2>&1 || falta "el compilador swiftc. Instálalo con: xcode-select --install"
[ -x /usr/bin/python3 ] || falta "/usr/bin/python3. Instálalo con: xcode-select --install"
[ -d /Applications/Claude.app ] || echo "Ojo: no encontré /Applications/Claude.app. La barra funciona igual, pero el clic no podrá abrir sesiones."

echo "Compilando..."
./construir.sh

echo "Agregando los hooks a ~/.claude/settings.json"
mkdir -p "$HOME/.claude"
/usr/bin/python3 hooks/ajustes.py instalar

echo "Copiando la app a $APP"
pkill -f "$APP/Contents/MacOS/Personita" || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "$APP/Contents/MacOS/Personita" >/dev/null || break
  sleep 0.3
done
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto build/Personita.app "$APP"

echo "Copiando el script de avisos a $CARPETA"
mkdir -p "$CARPETA"
chmod 700 "$CARPETA"
cp hooks/aviso-mac.py "$CARPETA/aviso-mac.py"
chmod 700 "$CARPETA/aviso-mac.py"

open -g "$APP"

echo
echo "Listo. Quedó la app en $APP y el script de avisos en $CARPETA."
echo "Los hooks de Personita quedaron en ~/.claude/settings.json (si ya existía, hay un respaldo al lado)."
echo "Las sesiones nuevas de Claude Code ya avisan; las que estaban abiertas, desde que las reinicies."
echo "Para desinstalar: ./desinstalar.sh"
