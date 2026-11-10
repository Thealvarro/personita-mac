#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Prueba instalar.sh y desinstalar.sh con un HOME temporal. No toca tu ~/.claude real,
# no compila (usa un construir.sh falso) y no abre ni cierra la app real.
set -u
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FALLAS=()
falla() { FALLAS+=("$1"); }

# Copia del proyecto con un construir.sh falso que arma una app vacía.
PROY="$TMP/proyecto"
mkdir -p "$PROY"
cp -R "$RAIZ/instalar.sh" "$RAIZ/desinstalar.sh" "$RAIZ/hooks" "$PROY/"
cat > "$PROY/construir.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
rm -rf build/Personita.app
mkdir -p build/Personita.app/Contents/MacOS
echo falso > build/Personita.app/Contents/MacOS/Personita
EOF
chmod +x "$PROY/construir.sh"

# open falso: anota lo que se quiso abrir.
mkdir -p "$TMP/bin"
printf '#!/bin/bash\necho "$@" >> "%s/abiertos"\n' "$TMP" > "$TMP/bin/open"
chmod +x "$TMP/bin/open"

nuevo_home() { H="$TMP/home-$1"; mkdir -p "$H/.claude"; }
instalar() { HOME="$H" PATH="$TMP/bin:$PATH" "$PROY/instalar.sh" >/dev/null 2>"$TMP/err"; }
desinstalar() { HOME="$H" PATH="$TMP/bin:$PATH" "$PROY/desinstalar.sh" >/dev/null 2>"$TMP/err"; }
ajustes() { echo "$H/.claude/settings.json"; }
igual_json() { /usr/bin/python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])))' "$1" "$2"; }
respaldos() { ls "$H/.claude/" | grep -c '^settings.json.respaldo-personita-' || true; }
# Cuenta los hooks de Personita por evento, como "evento:cantidad" ordenado.
propios() {
  /usr/bin/python3 - "$(ajustes)" "$H" <<'EOF'
import json, sys
d, h = json.load(open(sys.argv[1])), sys.argv[2]
s, a = h + "/.claude/personita-mac/aviso-mac.py", h + "/Applications/Personita.app"
propio = lambda x: s in [x.get("command")] + x.get("args", []) or a in x.get("args", [])
out = []
for ev, grupos in sorted(d.get("hooks", {}).items()):
    mios = [g.get("matcher") for g in grupos for x in g.get("hooks", []) if propio(x)]
    if mios:
        out.append(f"{ev}:{len(mios)}:{mios}")
print(" ".join(out))
EOF
}
ESPERADO="Notification:1:['permission_prompt|elicitation_dialog'] PostToolUse:1:[None] PreToolUse:1:['AskUserQuestion'] SessionStart:1:[None] Stop:1:[None] UserPromptSubmit:1:[None]"

# 1. settings.json inexistente.
nuevo_home vacio
instalar || falla "inexistente: instalar falló: $(cat "$TMP/err")"
[ -f "$(ajustes)" ] || falla "inexistente: no se creó settings.json"
[ "$(propios)" = "$ESPERADO" ] || falla "inexistente: hooks inesperados: $(propios)"
[ "$(respaldos)" = 0 ] || falla "inexistente: no debía haber respaldo"
[ -f "$H/Applications/Personita.app/Contents/MacOS/Personita" ] || falla "inexistente: no se copió la app"
[ "$(stat -f %Lp "$H/.claude/personita-mac")" = 700 ] || falla "inexistente: carpeta sin permisos 700"
[ "$(stat -f %Lp "$H/.claude/personita-mac/aviso-mac.py")" = 700 ] || falla "inexistente: script sin permisos 700"
cmp -s "$RAIZ/hooks/aviso-mac.py" "$H/.claude/personita-mac/aviso-mac.py" || falla "inexistente: el script copiado no es igual"
grep -q "$H/Applications/Personita.app" "$TMP/abiertos" 2>/dev/null || falla "inexistente: no abrió la app"
desinstalar || falla "inexistente: desinstalar falló: $(cat "$TMP/err")"
[ "$(cat "$(ajustes)")" = "{}" ] || falla "inexistente: tras desinstalar debía quedar {}"
[ ! -e "$H/Applications/Personita.app" ] || falla "inexistente: no borró la app"
[ ! -e "$H/.claude/personita-mac" ] || falla "inexistente: no borró la carpeta de avisos"
desinstalar || falla "inexistente: desinstalar dos veces falló"

# 2. settings.json con hooks ajenos y otras llaves.
nuevo_home ajeno
cat > "$(ajustes)" <<'EOF'
{
  "model": "opus",
  "permissions": {"allow": ["Bash(ls:*)"], "deny": []},
  "env": {"ALGO": "valor con ñ"},
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/mi-stop.sh"}]}],
    "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "prettier"}]}],
    "Notification": [{"matcher": "permission_prompt|elicitation_dialog", "hooks": [{"type": "command", "command": "say hola"}]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "echo compacto"}]}]
  },
  "statusLine": {"type": "command", "command": "echo x"}
}
EOF
chmod 640 "$(ajustes)"
cp "$(ajustes)" "$TMP/original.json"
instalar || falla "ajeno: instalar falló: $(cat "$TMP/err")"
[ "$(propios)" = "$ESPERADO" ] || falla "ajeno: hooks inesperados: $(propios)"
[ "$(respaldos)" = 1 ] || falla "ajeno: debía haber 1 respaldo, hay $(respaldos)"
R="$(ls "$H/.claude/"settings.json.respaldo-personita-* 2>/dev/null | head -1)"
cmp -s "$R" "$TMP/original.json" || falla "ajeno: el respaldo no es igual al original"
[ "$(stat -f %Lp "$(ajustes)")" = 640 ] || falla "ajeno: no conservó los permisos del archivo"
/usr/bin/python3 - "$TMP/original.json" "$(ajustes)" <<'EOF' || falla "ajeno: cambió algo ajeno"
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
for k in a:
    if k != "hooks" and a[k] != b[k]:
        sys.exit(1)
for ev, grupos in a["hooks"].items():
    if b["hooks"][ev][:len(grupos)] != grupos:
        sys.exit(1)
EOF
cp "$(ajustes)" "$TMP/instalado.json"
instalar || falla "ajeno: segunda instalación falló"
igual_json "$TMP/instalado.json" "$(ajustes)" || falla "ajeno: instalar dos veces cambió el resultado"
[ "$(respaldos)" = 1 ] || falla "ajeno: la segunda instalación sin cambios no debía crear respaldo"
desinstalar || falla "ajeno: desinstalar falló: $(cat "$TMP/err")"
igual_json "$TMP/original.json" "$(ajustes)" || falla "ajeno: desinstalar no dejó el JSON como el original"
[ "$(respaldos)" = 2 ] || falla "ajeno: desinstalar debía crear un respaldo"
desinstalar || falla "ajeno: desinstalar dos veces falló"
igual_json "$TMP/original.json" "$(ajustes)" || falla "ajeno: desinstalar dos veces cambió el JSON"

# 3. JSON corrupto: no se toca y sale con error.
nuevo_home corrupto
printf '{"hooks": {"Stop": [' > "$(ajustes)"
cp "$(ajustes)" "$TMP/corrupto.json"
if instalar; then falla "corrupto: instalar debía fallar"; fi
cmp -s "$(ajustes)" "$TMP/corrupto.json" || falla "corrupto: instalar modificó el archivo"
if desinstalar; then falla "corrupto: desinstalar debía fallar"; fi
cmp -s "$(ajustes)" "$TMP/corrupto.json" || falla "corrupto: desinstalar modificó el archivo"
[ "$(respaldos)" = 0 ] || falla "corrupto: no debía crear respaldos"

if [ ${#FALLAS[@]} -eq 0 ]; then
  echo "TODO OK"
else
  printf 'FALLA: %s\n' "${FALLAS[@]}"
  exit 1
fi
