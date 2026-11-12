# Changelog

## 1.1.0 - 2026-11-12

- con la barra escondida, un aviso nuevo ya no la abre: la flecha se pone naranja y parpadea hasta que la abras

## 1.0.0 - 2026-11-10

Primera versión pública.

- barra flotante pegada al borde derecho de la pantalla, sin ícono en el Dock ni en la barra de menú
- cuadro superior con la última sesión y una personita de pixel art que se mueve; debajo, las sesiones anteriores
- naranja para la sesión que terminó y no has abierto, amarillo para la que te está esperando, y un punto en la fila para las que no has visto
- título de la sesión y, en chico, la carpeta del proyecto
- clic en una sesión para abrirla en la app de escritorio de Claude
- se esconde dejando solo una flecha, se abre sola cuando llega un aviso y muestra el nombre completo al dejar el mouse sobre uno cortado
- hook de Claude Code (`aviso-mac.py`) que anota los eventos en `~/.claude/personita-mac/avisos.jsonl`
- lectura de solo lectura de las sesiones y de las no leídas de la app de Claude
- instalador y desinstalador que compilan en el Mac del usuario y respaldan `~/.claude/settings.json`
- función opcional, apagada por defecto, para un iPad compañero en la red local
- pruebas de lógica con `./Pruebas/probar.sh`
