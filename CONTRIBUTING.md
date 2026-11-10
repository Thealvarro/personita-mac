# Contribuir

Gracias por querer aportar. Los cambios chicos y enfocados se revisan rápido; uno que mezcla varias cosas se devuelve.

## Compilar y probar

Necesitas macOS 13 o superior y las Command Line Tools de Xcode.

```zsh
./construir.sh        # deja build/Personita.app
./Pruebas/probar.sh   # corre las pruebas de lógica en una carpeta temporal
```

Antes de abrir un pull request, las pruebas tienen que pasar. Si cambias el comportamiento de `Fuentes/Avisos.swift`, `Receptor.swift`, `Emisor.swift`, `NoLeidas.swift` o `AbrirSesion.swift`, agrega o ajusta la prueba correspondiente en `Pruebas/main.swift`.

## Reglas del proyecto

- El código y los comentarios van en español, igual que el resto.
- Sigue el estilo del archivo que tocas; no reformatees lo que no estás cambiando.
- Nada de telemetría, analítica ni conexiones a internet. La app no sale a internet y eso no cambia.
- Todo lo que lee de la app de Claude es solo lectura. No escribas en esos archivos.
- Lo que llega por red o desde archivos ajenos se trata como no confiable: se valida y nunca se usa para armar comandos ni rutas.

## Licencia

Al enviar una contribución aceptas que quede bajo GPL-3.0-or-later, junto con el término adicional del archivo `NOTICE`.
