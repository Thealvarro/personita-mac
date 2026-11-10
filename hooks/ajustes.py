#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Agrega o quita los hooks de Personita en ~/.claude/settings.json.
# Uso: ajustes.py instalar|desinstalar
# Nunca toca hooks ajenos. Reconoce los suyos porque apuntan al script o a la app de Personita.
# Antes de escribir deja un respaldo y escribe de forma atómica (temporal + rename).
# Nunca imprime el contenido del archivo.
import json, os, shutil, stat, sys, tempfile, time

HOME = os.environ["HOME"]
AJUSTES = os.path.join(HOME, ".claude", "settings.json")
SCRIPT = os.path.join(HOME, ".claude", "personita-mac", "aviso-mac.py")
APP = os.path.join(HOME, "Applications", "Personita.app")


def hook(*args):
    return {"type": "command", "command": "/usr/bin/python3", "args": [SCRIPT, *args], "async": True}


# (evento, matcher o None, hook)
PROPIOS = [
    ("Notification", "permission_prompt|elicitation_dialog", hook("espera")),
    ("PreToolUse", "AskUserQuestion", hook("espera")),
    ("PostToolUse", None, hook("sigue")),
    ("UserPromptSubmit", None, hook("sigue")),
    ("Stop", None, hook("stop")),
    ("SessionStart", None, {"type": "command", "command": "/usr/bin/open", "args": ["-g", APP], "async": True}),
]


def es_propio(h):
    if not isinstance(h, dict):
        return False
    partes = [h.get("command")] + (h.get("args") if isinstance(h.get("args"), list) else [])
    return SCRIPT in partes or APP in partes


def falla(mensaje):
    print(mensaje, file=sys.stderr)
    sys.exit(1)


def leer():
    if not os.path.exists(AJUSTES):
        return None
    try:
        with open(AJUSTES, encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError):
        falla(f"No pude leer {AJUSTES} como JSON. No lo toqué: revísalo y vuelve a intentar.")
    hooks = datos.get("hooks", {}) if isinstance(datos, dict) else None
    if not isinstance(hooks, dict) or not all(isinstance(v, list) for v in hooks.values()):
        falla(f"{AJUSTES} no tiene la forma esperada. No lo toqué.")
    return datos


def instalar(datos):
    hooks = datos.setdefault("hooks", {})
    for evento, matcher, nuevo in PROPIOS:
        grupos = hooks.setdefault(evento, [])
        ya_esta = any(
            isinstance(g, dict) and g.get("matcher") == matcher
            and any(es_propio(h) for h in g.get("hooks", []) if isinstance(g.get("hooks"), list))
            for g in grupos
        )
        if not ya_esta:
            grupo = {"matcher": matcher} if matcher else {}
            grupo["hooks"] = [nuevo]
            grupos.append(grupo)


def desinstalar(datos):
    hooks = datos.get("hooks")
    if not isinstance(hooks, dict):
        return
    for evento in list(hooks):
        grupos = []
        for g in hooks[evento]:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(es_propio(h) for h in g["hooks"]):
                g["hooks"] = [h for h in g["hooks"] if not es_propio(h)]
                if not g["hooks"]:
                    continue
            grupos.append(g)
        if grupos:
            hooks[evento] = grupos
        else:
            del hooks[evento]
    if not hooks:
        del datos["hooks"]


def respaldar():
    base = AJUSTES + ".respaldo-personita-" + time.strftime("%Y%m%d-%H%M%S")
    ruta, n = base, 2
    while os.path.exists(ruta):
        ruta, n = f"{base}-{n}", n + 1
    shutil.copy2(AJUSTES, ruta)


def escribir(datos):
    modo = stat.S_IMODE(os.stat(AJUSTES).st_mode) if os.path.exists(AJUSTES) else 0o600
    carpeta = os.path.dirname(AJUSTES)
    os.makedirs(carpeta, exist_ok=True)
    fd, temporal = tempfile.mkstemp(dir=carpeta, prefix=".settings.json.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(datos, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(temporal, modo)
        os.replace(temporal, AJUSTES)
    except BaseException:
        os.remove(temporal)
        raise


def main():
    accion = sys.argv[1] if len(sys.argv) > 1 else ""
    if accion not in ("instalar", "desinstalar"):
        falla("Uso: ajustes.py instalar|desinstalar")
    datos = leer()
    if datos is None:
        if accion == "desinstalar":
            return
        datos = {}
    antes = json.dumps(datos, sort_keys=True)
    instalar(datos) if accion == "instalar" else desinstalar(datos)
    if json.dumps(datos, sort_keys=True) == antes and os.path.exists(AJUSTES):
        return
    if os.path.exists(AJUSTES):
        respaldar()
    escribir(datos)


main()
