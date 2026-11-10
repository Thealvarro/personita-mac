# Política de seguridad

## Versiones con soporte

Solo la última versión publicada. Si encuentras algo en una versión anterior, primero revisa si sigue pasando en la última.

## Cómo reportar una vulnerabilidad

Hazlo en privado desde la pestaña Security del repositorio en GitHub, con el botón Report a vulnerability. No abras un issue público ni un pull request con los detalles hasta que esté corregido.

Incluye, si puedes:

- qué versión usas y en qué versión de macOS
- qué componente afecta
- los pasos para reproducirlo
- qué logra alguien que lo aproveche
- una prueba de concepto, si la tienes

Respondo lo antes que pueda, pero esto lo mantiene una sola persona, así que puede tardar unos días.

## Qué está dentro del alcance

- la app (`Fuentes/`), incluida la lectura de los archivos de la app de Claude
- el script del hook `aviso-mac.py` y los hooks que se agregan a `~/.claude/settings.json`
- el instalador y el desinstalador (`instalar.sh`, `desinstalar.sh`)
- el receptor de red opcional del puerto 8081 y el envío opcional al iPad

## Qué queda fuera

- fallos de macOS, de Claude Code o de la app de escritorio de Claude: repórtalos a quien corresponda
- ataques que ya requieren acceso a tu cuenta de usuario en el Mac, porque desde ahí se puede leer o escribir los mismos archivos que usa Personita
- la app del iPad, que no forma parte de este repositorio
