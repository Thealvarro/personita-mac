// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import SwiftUI

private let azul = Color(rgb: 0x16273a)
private let azulCuadro = Color(rgb: 0x22364d)
private let coral = Color(rgb: 0xee6c4d)
private let celeste = Color(rgb: 0xc9d6ea)
private let azulCuadroEncima = Color(rgb: 0x2c4563)
private let coralEncima = Color(rgb: 0xd95b3e)
private let amarillo = Color(rgb: 0xf2c14e)
private let amarilloEncima = Color(rgb: 0xe0ae35)

// Respuesta visible al apretar: baja la opacidad mientras el botón está presionado.
struct Presionable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private let formatoHora: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

final class Estado: ObservableObject {
    @Published var avisos: [Aviso] = [] {
        didSet { emisor?.cambio(avisos, sinVer) }
    }
    // Sesiones con el puntito azul de no leído en Claude; si no se puede leer, las que terminaron mientras
    // el dueño miraba otra y que todavía no abre en Claude.
    @Published var sinVer: Set<String> = [] {
        didSet {
            rutasSinVer = rutasSinVer.filter { sinVer.contains($0.key) }
            emisor?.cambio(avisos, sinVer)
        }
    }
    @Published var tenue = false
    @Published var escondida = UserDefaults.standard.bool(forKey: "escondida")
    var alCambiar: (_ animado: Bool) -> Void = { _ in }
    // El mouse entra o sale de un proyecto (para mostrar su nombre completo).
    var alPasar: (_ aviso: Aviso, _ dentro: Bool) -> Void = { _, _ in }
    // Fijada: no se esconde sola al sacar el mouse.
    var fijada = false
    // Manda la lista al iPad; al asignarlo se envía el estado actual.
    var emisor: Emisor? {
        didSet { emisor?.cambio(avisos, sinVer) }
    }
    private var firma: String?
    private var reloj: Timer?
    // Archivo de la app de Claude de cada sesión sin ver y su última fecha de modificación conocida.
    private var rutasSinVer: [String: (ruta: URL, fecha: Date?)] = [:]
    // No leídas según el Local Storage de Claude (nil: no se pudo leer y manda la heurística) y la firma de sus archivos.
    private var noLeidas: Set<String>?
    private var firmaLeveldb: String?
    // La lista que sale del archivo de avisos, sin las no leídas agregadas al final.
    private var base: [Aviso] = []

    // Lee el archivo al partir (sin parpadear ni abrir la barra) y lo revisa cada segundo por tamaño y fecha.
    func arrancar() {
        revisar(primera: true)
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.revisar(primera: false); self?.emisor?.tick() }
    }

    private func revisar(primera: Bool) {
        let cambioNoLeidas = revisarNoLeidas()
        if noLeidas == nil && !sinVer.isEmpty { revisarFocos() }
        let atributos = try? FileManager.default.attributesOfItem(atPath: rutaAvisos.path)
        let nueva = atributos.map { "\($0[.size] ?? 0)|\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" }
        if !primera && nueva == firma && !cambioNoLeidas { return }
        firma = nueva
        let sesiones = leerSesiones()
        let base = conTitulos(reconstruir(leerAvisos()), sesiones)
        let lista = conNoLeidas(base, noLeidas: noLeidas, sesiones: sesiones)
        // Con no leídas, sin ver sigue al conjunto aunque la lista no cambie; con la heurística, solo si cambió.
        if lista != avisos || noLeidas != nil {
            let nuevo = calcularSinVer(sinVer, noLeidas: noLeidas, antes: avisos, despues: lista, sesiones: sesiones)
            if nuevo != sinVer { sinVer = nuevo }
        }
        guard lista != avisos else { return }
        // Las filas agregadas al final no cuentan como aviso nuevo.
        let hayNuevo = !primera && hayAvisoNuevo(antes: self.base, despues: base)
        self.base = base
        for sesion in sinVer where rutasSinVer[sesion] == nil {
            if let ruta = sesiones.rutas[sesion] { rutasSinVer[sesion] = (ruta, fechaModificacion(ruta)) }
        }
        if hayNuevo { emisor?.marcarNuevo() }
        avisos = lista
        if hayNuevo {
            parpadear()
            // Con un aviso nuevo la barra se abre sola.
            if escondida { return DispatchQueue.main.async { self.alternar() } }
        }
        DispatchQueue.main.async { self.alCambiar(false) }
    }

    // Relee las no leídas solo si cambió el tamaño o la fecha de sus archivos; dice si cambió el conjunto.
    private func revisarNoLeidas() -> Bool {
        let nueva = firmaNoLeidas()
        guard nueva != firmaLeveldb else { return false }
        firmaLeveldb = nueva
        let conjunto = leerNoLeidas()
        guard conjunto != noLeidas else { return false }
        noLeidas = conjunto
        return true
    }

    private func conTitulos(_ lista: [Aviso], _ sesiones: Sesiones = leerSesiones()) -> [Aviso] {
        lista.map { var a = $0; a.titulo = sesiones.titulos[a.sesion]; a.carpeta = sesiones.carpetas[a.sesion]; return a }
    }

    // Solo relee el foco de los archivos de sesiones sin ver que cambiaron; si el dueño la abrió en Claude, sale.
    private func revisarFocos() {
        for (sesion, guardado) in rutasSinVer {
            let fecha = fechaModificacion(guardado.ruta)
            guard fecha != guardado.fecha else { continue }
            rutasSinVer[sesion]?.fecha = fecha
            if let foco = leerFoco(ruta: guardado.ruta), let aviso = avisos.first(where: { $0.sesion == sesion }), foco >= aviso.hora {
                sinVer.remove(sesion)
            }
        }
    }

    private func fechaModificacion(_ ruta: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: ruta.path))?[.modificationDate] as? Date
    }

    private func parpadear() {
        var veces = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] reloj in
            guard let self else { return reloj.invalidate() }
            self.tenue.toggle()
            veces += 1
            if veces == 8 {
                reloj.invalidate()
                self.tenue = false
            }
        }
    }

    func alternar() {
        fijada = false
        escondida.toggle()
        // Los títulos se refrescan al terminar el deslizamiento: leerlos demora y trabaría el comienzo.
        if !escondida {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, !self.escondida else { return }
                let lista = self.conTitulos(self.avisos)
                if lista != self.avisos { self.avisos = lista }
            }
        }
        UserDefaults.standard.set(escondida, forKey: "escondida")
        alCambiar(true)
    }

    func elegir(_ aviso: Aviso) {
        alPasar(aviso, false)
        // Con las no leídas de Claude la marca se va sola cuando Claude la quita.
        if noLeidas == nil { sinVer.remove(aviso.sesion) }
        abrirSesion(aviso)
        // Tras elegir un proyecto la barra queda abierta hasta que se apriete la flecha.
        fijada = true
    }
}

// Rectángulo con solo las esquinas izquierdas redondeadas.
struct IzquierdaRedondeada: Shape {
    let radio: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + radio, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX, y: r.minY + radio), radius: radio)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radio))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + radio, y: r.maxY), radius: radio)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Raiz: View {
    @ObservedObject var estado: Estado
    var alMedir: (CGSize) -> Void = { _ in }
    var poseFija: Pose? = nil  // solo para renderizar imágenes de revisión
    @State private var encimaCuadro = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            lengueta
            panel
        }
        .fixedSize()
        // Tamaño ideal del contenido (no depende del ancho actual de la ventana). Con onPreferenceChange
        // solo llegaba un primer valor en cero y nunca los cambios, así que la ventana no seguía al contenido.
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { alMedir(geo.size) }
                .onChange(of: geo.size) { alMedir($0) }
        })
        .contextMenu {
            Button("Desarrollado por SICS") { NSWorkspace.shared.open(URL(string: "https://alvarocofre.dev")!) }
            Divider()
            Button("Salir de Personita") { NSApp.terminate(nil) }
        }
    }

    private var lengueta: some View {
        let marcada = estado.escondida && !estado.sinVer.isEmpty
        return Image(systemName: estado.escondida ? "chevron.left" : "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 24, height: 56)
            .background(IzquierdaRedondeada(radio: 8).fill(marcada ? coral : azul))
            .opacity(estado.escondida && estado.tenue ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.2), value: estado.tenue)
            .contentShape(Rectangle())
            .onTapGesture { estado.alternar() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            cuadro
            if estado.avisos.count > 1 {
                Text("Anteriores")
                    .font(.system(size: 11))
                    .foregroundColor(Color(rgb: 0x8d93a0))
                VStack(spacing: 2) {
                    ForEach(estado.avisos.dropFirst(), id: \.sesion) { aviso in
                        Fila(aviso: aviso, sinVer: estado.sinVer.contains(aviso.sesion), alPasar: { estado.alPasar(aviso, $0) }) { estado.elegir(aviso) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 196, alignment: .topLeading)
        .background(IzquierdaRedondeada(radio: 12).fill(azul))
    }

    private var cuadro: some View {
        let ultimo = estado.avisos.first
        let marcado = ultimo.map { estado.sinVer.contains($0.sesion) } ?? false
        return Button { if let ultimo { estado.elegir(ultimo) } } label: { contenidoCuadro(marcado: marcado, ultimo: ultimo) }
            .buttonStyle(Presionable())
            .onHover { dentro in
                encimaCuadro = dentro
                if let ultimo { estado.alPasar(ultimo, dentro) }
            }
    }

    private func contenidoCuadro(marcado: Bool, ultimo: Aviso?) -> some View {
        // Amarillo mientras Claude espera al dueño; el coral de la sesión sin ver va por encima.
        let amarillento = !marcado && ultimo?.esperando == true
        let fondo = marcado ? (encimaCuadro ? coralEncima : coral) : amarillento ? (encimaCuadro ? amarilloEncima : amarillo) : (encimaCuadro ? azulCuadroEncima : azulCuadro)
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ultimo?.esperando == true ? "Te está esperando" : "Último terminado")
                    .font(.system(size: 11))
                    .foregroundColor(marcado ? .white : (amarillento ? azul : celeste))
                if let ultimo {
                    if let carpeta = ultimo.carpetaVisible {
                        Text(verbatim: carpeta)
                            .font(.system(size: 11))
                            .foregroundColor((marcado ? Color.white : (amarillento ? azul : celeste)).opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(verbatim: ultimo.nombre)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(amarillento ? azul : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Text(ultimo.esperando ? "te está esperando · \(formatoHora.string(from: ultimo.hora))" : "terminó a las \(formatoHora.string(from: ultimo.hora))")
                        .font(.system(size: 12))
                        .foregroundColor(marcado ? .white : (amarillento ? azul : Color(rgb: 0xe9eaed)))
                        // "te está esperando · HH:mm" no cabe junto al monito: se achica un poco en vez de saltar de línea.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Sin avisos todavía")
                        .font(.system(size: 12))
                        .foregroundColor(Color(rgb: 0xe9eaed))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Se mueve solo con la barra abierta; escondida, la línea de tiempo queda en pausa.
            TimelineView(.animation(minimumInterval: Sprites.paso, paused: estado.escondida)) { linea in
                Monito(pose: poseFija ?? Sprites.pose(en: linea.date))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(fondo))
        .opacity(!estado.escondida && estado.tenue ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: estado.tenue)
        .contentShape(Rectangle())
    }
}

struct Fila: View {
    let aviso: Aviso
    let sinVer: Bool
    let alPasar: (Bool) -> Void
    let alElegir: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: alElegir) { contenido }
            .buttonStyle(Presionable())
            .onHover { dentro in
                encima = dentro
                alPasar(dentro)
            }
    }

    private var contenido: some View {
        HStack(spacing: 6) {
            if sinVer {
                Circle().fill(aviso.esperando ? azul : coral).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let carpeta = aviso.carpetaVisible {
                    Text(verbatim: carpeta)
                        .font(.system(size: 10))
                        .foregroundColor(aviso.esperando ? azul.opacity(0.7) : Color(rgb: 0x8d93a0))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(verbatim: aviso.nombre)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Text(formatoHora.string(from: aviso.hora))
        }
        .font(.system(size: 12))
        .foregroundColor(aviso.esperando ? azul : celeste)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(aviso.esperando ? (encima ? amarilloEncima : amarillo) : (encima ? azulCuadro : .clear)))
        .contentShape(Rectangle())
    }
}

// Nombre completo del proyecto que está bajo el mouse; va en su propia ventana, a la izquierda de la barra.
struct Etiqueta: View {
    let texto: String

    var body: some View {
        Text(verbatim: texto)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(azul))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(azulCuadroEncima, lineWidth: 1))
    }
}
