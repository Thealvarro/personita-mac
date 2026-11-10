// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import AppKit
import SwiftUI

// Acepta el primer clic aunque la ventana no esté activa (el panel nunca se activa).
final class Anfitrion: NSHostingView<Raiz> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Delegado: NSObject, NSApplicationDelegate {
    let estado = Estado()
    var ventana: NSPanel!
    var anfitrion: Anfitrion!
    var espera: Timer?
    var receptor: Receptor?
    var medido = CGSize.zero
    var finAnimacion = Date.distantPast
    var deslizamiento = 0  // cuenta los deslizamientos para saber cuál es el último
    var etiqueta: NSPanel!
    let textoEtiqueta = NSHostingController(rootView: Etiqueta(texto: ""))
    var encima: Aviso?
    var esperaEtiqueta: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ventana = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ventana.level = .floating
        ventana.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ventana.isOpaque = false
        ventana.backgroundColor = .clear
        ventana.hasShadow = false
        ventana.hidesOnDeactivate = false
        ventana.isMovable = false

        // Ventana aparte para el nombre completo del proyecto bajo el mouse; no recibe clics ni eventos del mouse.
        etiqueta = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        etiqueta.level = .floating
        etiqueta.collectionBehavior = ventana.collectionBehavior
        etiqueta.isOpaque = false
        etiqueta.backgroundColor = .clear
        etiqueta.hasShadow = false
        etiqueta.hidesOnDeactivate = false
        etiqueta.ignoresMouseEvents = true
        // Sin esto la vista le impone a la ventana el alto de una sola línea y los nombres largos se cortan.
        textoEtiqueta.sizingOptions = []
        etiqueta.contentView = textoEtiqueta.view

        // La vista SwiftUI va dentro de un contenedor: al esconder, la ventana se achica a la lengüeta
        // y la vista se corre para que solo quede visible esa parte.
        ventana.contentView = NSView()
        // La vista informa su tamaño ideal cada vez que cambia; la ventana lo sigue.
        anfitrion = Anfitrion(rootView: Raiz(estado: estado, alMedir: { [weak self] tam in
            guard let self, tam != self.medido else { return }
            self.medido = tam
            self.ubicar(animado: false)
        }))
        ventana.contentView?.addSubview(anfitrion)

        // Detecta cuándo el puntero entra o sale de la barra (panel + lengüeta).
        ventana.contentView?.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))

        estado.alCambiar = { [weak self] animado in self?.ubicar(animado: animado) }
        estado.alPasar = { [weak self] aviso, dentro in self?.pasar(aviso, dentro: dentro) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.ubicar(animado: false)
        }
        estado.arrancar()
        receptor = Receptor(avisos: { [estado] in estado.avisos }, abrir: { [estado] in estado.elegir($0) })
        estado.emisor = Emisor()
        ubicar(animado: false)
        ventana.orderFrontRegardless()
    }

    @objc func mouseEntered(with event: NSEvent) { espera?.invalidate() }

    // Solo hay salida si antes hubo entrada. Pasada la espera se vuelve a mirar dónde está el puntero,
    // así las salidas falsas por el cambio de frame al esconder o mostrar no cierran nada.
    @objc func mouseExited(with event: NSEvent) {
        espera?.invalidate()
        guard !estado.escondida else { return }
        espera = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, !self.estado.escondida, !self.estado.fijada, !self.ventana.frame.contains(NSEvent.mouseLocation) else { return }
            self.estado.alternar()
        }
    }

    // La salida de un proyecto y la entrada al siguiente llegan por separado: se decide en la vuelta siguiente.
    func pasar(_ aviso: Aviso, dentro: Bool) {
        if dentro {
            encima = aviso
        } else if encima?.sesion == aviso.sesion {
            encima = nil
        }
        DispatchQueue.main.async { self.ponerEtiqueta() }
    }

    // Aparece tras 0,3 s sobre un proyecto; si ya estaba a la vista, cambia de nombre al tiro.
    func ponerEtiqueta() {
        esperaEtiqueta?.invalidate()
        guard let aviso = encima, !estado.escondida else { return etiqueta.orderOut(nil) }
        if etiqueta.isVisible { return mostrarEtiqueta(aviso.nombre) }
        esperaEtiqueta = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.mostrarEtiqueta(aviso.nombre)
        }
    }

    // A la izquierda de la barra, a 6 pt, centrada en la altura del mouse y dentro de la pantalla.
    func mostrarEtiqueta(_ texto: String) {
        guard let pantalla = NSScreen.screens.first else { return }
        let area = pantalla.visibleFrame
        textoEtiqueta.rootView = Etiqueta(texto: texto)
        let tam = textoEtiqueta.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        let y = min(max(NSEvent.mouseLocation.y - tam.height / 2, area.minY), area.maxY - tam.height)
        etiqueta.setFrame(NSRect(x: ventana.frame.minX - 6 - tam.width, y: y, width: tam.width, height: tam.height), display: true)
        etiqueta.orderFrontRegardless()
    }

    // Pega la ventana al borde derecho de la pantalla principal, centrada en vertical.
    func ubicar(animado: Bool) {
        guard let pantalla = NSScreen.screens.first else { return }
        let area = pantalla.visibleFrame
        let tam = medido == .zero ? anfitrion.fittingSize : medido
        if estado.escondida {
            encima = nil
            ponerEtiqueta()
        }
        let ancho = estado.escondida ? 24 : tam.width
        let y = area.midY - tam.height / 2
        anfitrion.setFrameSize(tam)
        // Si el contenido cambia de tamaño a mitad de una animación, la nueva usa el tiempo que le quedaba a esa.
        if animado { finAnimacion = Date(timeIntervalSinceNow: 0.3) }
        let quedan = finAnimacion.timeIntervalSinceNow
        guard quedan > 0 else {
            // En reposo y escondida, la ventana mide solo la lengüeta y la vista se corre para dejarla a la vista.
            let alto = estado.escondida ? 56 : tam.height
            let marco = NSRect(x: area.maxX - ancho, y: area.midY - alto / 2, width: ancho, height: alto)
            return mover(marco, origen: NSPoint(x: 0, y: estado.escondida ? -(tam.height - 56) / 2 : 0), duracion: 0)
        }
        // Al deslizar, la ventana tiene el alto completo desde el comienzo y solo se anima lo horizontal: el contenido
        // no se mueve en vertical. Lo de arriba y abajo de la lengüeta es transparente, así que ese salto no se ve.
        let actual = ventana.frame
        mover(NSRect(x: actual.minX, y: y, width: actual.width, height: tam.height), origen: .zero, duracion: 0)
        deslizamiento += 1
        let este = deslizamiento
        mover(NSRect(x: area.maxX - ancho, y: y, width: ancho, height: tam.height), origen: .zero, duracion: quedan) { [weak self] in
            // Solo al terminar la última animación (las reemplazadas también llaman acá, antes de tiempo).
            guard let self, este == self.deslizamiento else { return }
            self.finAnimacion = .distantPast
            self.ubicar(animado: false)
        }
    }

    // Siempre por el animator: un setFrame directo no detiene una animación en curso y esta termina en el marco viejo.
    func mover(_ marco: NSRect, origen: NSPoint, duracion: TimeInterval, alTerminar: (() -> Void)? = nil) {
        // En un salto, la ventana y la vista se dibujan juntas en pantalla y no un cuadro antes una que otra.
        if duracion == 0 { ventana.disableScreenUpdatesUntilFlush() }
        NSAnimationContext.runAnimationGroup({ contexto in
            contexto.duration = duracion
            ventana.animator().setFrame(marco, display: true)
            anfitrion.animator().setFrameOrigin(origen)
        }, completionHandler: alTerminar)
        if duracion == 0 { CATransaction.flush() }  // la vista sale en la misma vuelta que la ventana
    }
}

@main
enum Personita {
    static func main() {
        // Instancia única: si ya hay otra corriendo, esta termina.
        let otras = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if otras.contains(where: { $0.processIdentifier != getpid() }) { exit(0) }
        let app = NSApplication.shared
        let delegado = Delegado()
        app.delegate = delegado
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
