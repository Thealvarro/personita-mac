#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
# Deja los avisos de Claude Code en ~/.claude/personita-mac/avisos.jsonl para Personita Mac.
# Lee el JSON del hook por stdin. Argumento opcional con el evento:
#   stop (o nada): terminó el turno; si el último mensaje termina en pregunta queda esperando.
#   espera: Claude pide permiso o hace una pregunta; marca la sesión como esperando.
#   sigue: el usuario respondió o avanzó; si la sesión estaba esperando, la desmarca.
#     Si la herramienta es wrap_up de la app de escritorio, su campo ask es la pregunta al usuario:
#     deja (o quita) una marca vacía en ~/.claude/personita-mac/pregunta/<session_id> y nada más.
#     El stop siguiente la lee (cuenta como pregunta) y la borra; un UserPromptSubmit también la borra.
#     En todo sigue (UserPromptSubmit y cada PostToolUse) la sesión está trabajando: deja una marca vacía en
#     ~/.claude/personita-mac/trabajando/<session_id> o le sube la fecha; el stop la borra. espera no la toca.
#     La barra la da por vieja a los 15 minutos (si se cortó con Esc no llega stop).
# Las sesiones que esperan tienen un archivo vacío en ~/.claude/personita-mac/esperando/<session_id>.
# Nunca falla ni demora al hook: cualquier error termina en silencio.
import json, os, re, sys, time

UUID = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')


def termina_en_pregunta(mensaje):
    if not isinstance(mensaje, str):
        return False
    lineas = [l for l in mensaje.splitlines() if l.strip()]
    return bool(lineas) and lineas[-1].rstrip(" \t*_`)\"»").endswith("?")


def main():
    evento = sys.argv[1] if len(sys.argv) > 1 else "stop"
    if evento not in ("stop", "espera", "sigue"):
        return
    datos = json.loads(sys.stdin.read())
    sesion, cwd = datos.get("session_id"), datos.get("cwd")
    if not isinstance(sesion, str) or not UUID.match(sesion):
        return
    carpeta = os.path.expanduser("~/.claude/personita-mac")
    marca = os.path.join(carpeta, "esperando", sesion)
    pregunta = os.path.join(carpeta, "pregunta", sesion)
    trabajando = os.path.join(carpeta, "trabajando", sesion)
    if evento == "stop" and os.path.exists(trabajando):
        os.remove(trabajando)
    if evento == "sigue":
        # Barato: si la marca ya existe solo se le sube la fecha.
        try:
            os.utime(trabajando)
        except FileNotFoundError:
            os.makedirs(carpeta, mode=0o700, exist_ok=True)
            os.chmod(carpeta, 0o700)
            os.makedirs(os.path.dirname(trabajando), mode=0o700, exist_ok=True)
            os.chmod(os.path.dirname(trabajando), 0o700)
            os.close(os.open(trabajando, os.O_WRONLY | os.O_CREAT, 0o600))
        herramienta = datos.get("tool_name")
        if herramienta == "mcp__ccd_turn__wrap_up":
            entrada = datos.get("tool_input")
            ask = entrada.get("ask") if isinstance(entrada, dict) else None
            if isinstance(ask, str) and ask.strip():
                os.makedirs(carpeta, mode=0o700, exist_ok=True)
                os.chmod(carpeta, 0o700)
                os.makedirs(os.path.dirname(pregunta), mode=0o700, exist_ok=True)
                os.chmod(os.path.dirname(pregunta), 0o700)
                os.close(os.open(pregunta, os.O_WRONLY | os.O_CREAT, 0o600))
            elif os.path.exists(pregunta):
                os.remove(pregunta)
            return
        # UserPromptSubmit no trae tool_name: el usuario ya contestó, la pregunta quedó vieja.
        if not herramienta and os.path.exists(pregunta):
            os.remove(pregunta)
    hay_marca = os.path.exists(marca)
    # En stop, la marca pregunta se consume siempre; si estaba, el turno queda esperando.
    hay_pregunta = evento == "stop" and os.path.exists(pregunta)
    if hay_pregunta:
        os.remove(pregunta)
    # sigue se llama muy seguido: sin marca no hay nada que hacer.
    if (evento == "sigue" and not hay_marca) or (evento == "espera" and hay_marca):
        return
    if not isinstance(cwd, str):
        return
    proyecto = "".join(c for c in os.path.basename(cwd.rstrip("/")) if c.isprintable())[:40]
    if not proyecto.strip():
        return
    if evento == "sigue":
        tipo = "respondio"
    elif evento == "espera" or hay_pregunta or termina_en_pregunta(datos.get("last_assistant_message")):
        tipo = "espera"
    else:
        tipo = "termino"
    os.makedirs(carpeta, mode=0o700, exist_ok=True)
    os.chmod(carpeta, 0o700)
    if tipo == "espera":
        os.makedirs(os.path.dirname(marca), mode=0o700, exist_ok=True)
        os.chmod(os.path.dirname(marca), 0o700)
        os.close(os.open(marca, os.O_WRONLY | os.O_CREAT, 0o600))
    elif hay_marca:
        os.remove(marca)
    ruta = os.path.join(carpeta, "avisos.jsonl")
    linea = json.dumps({"proyecto": proyecto, "sesion": sesion, "cwd": cwd, "hora": int(time.time()), "tipo": tipo}, ensure_ascii=False)
    with os.fdopen(os.open(ruta, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600), "a", encoding="utf-8") as f:
        f.write(linea + "\n")
    os.chmod(ruta, 0o600)
    with open(ruta, encoding="utf-8") as f:
        lineas = f.readlines()
    if len(lineas) > 200:
        temporal = ruta + ".tmp"
        with os.fdopen(os.open(temporal, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
            f.writelines(lineas[-200:])
        os.replace(temporal, ruta)


try:
    main()
except Exception:
    pass
sys.exit(0)
