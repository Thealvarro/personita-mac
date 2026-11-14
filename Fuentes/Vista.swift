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
private let celesteTrabajo = Color(rgb: 0x59b9c7)

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
        didSet { ordenar(); emisor?.cambio(paraIpad, sinVer) }
    }
    // Sesiones con el puntito azul de no leído en Claude; si no se puede leer, las que terminaron mientras
    // el dueño miraba otra y que todavía no abre en Claude.
    @Published var sinVer: Set<String> = [] {
        didSet {
            rutasSinVer = rutasSinVer.filter { sinVer.contains($0.key) }
            ordenar()
            emisor?.cambio(paraIpad, sinVer)
        }
    }
    // Sesiones trabajando ahora (marca de menos de 15 min) y las que trabajan sin estar en la lista, que se
    // muestran al final. No pasan por avisos: no cuentan como aviso nuevo ni se mandan al iPad.
    @Published var trabajando: Set<String> = [] {
        didSet { ordenar() }
    }
    @Published var extras: [Aviso] = [] {
        didSet { ordenar() }
    }
    // Las filas en orden de pantalla (ver ordenPantalla); el panel de arriba es la primera.
    @Published private(set) var filas: [Aviso] = []
    // Si la barra no cabe en el alto de la pantalla, cuántas filas se muestran (nil: todas).
    @Published var tope: Int?
    var visibles: [Aviso] { tope.map { Array(filas.prefix($0)) } ?? filas }
    // Al iPad va el orden de pantalla sin las filas extra de trabajando.
    private var paraIpad: [Aviso] {
        let enLista = Set(avisos.map(\.sesion))
        return filas.filter { enLista.contains($0.sesion) }
    }
    @Published var tenue = false
    // Barra escondida con un aviso nuevo sin atender: la lengüeta queda coral y parpadea hasta que se abra.
    @Published var avisando = false
    @Published var escondida = UserDefaults.standard.bool(forKey: "escondida")
    // Elegida en el menú del clic derecho: escondida y con un aviso nuevo, la barra se abre sola en vez de solo avisar con la lengüeta.
    @Published var abrirSola = UserDefaults.standard.bool(forKey: "abrirSola") {
        didSet { UserDefaults.standard.set(abrirSola, forKey: "abrirSola") }
    }
    var alCambiar: (_ animado: Bool) -> Void = { _ in }
    // El mouse entra o sale de un proyecto (para mostrar su nombre completo).
    var alPasar: (_ aviso: Aviso, _ dentro: Bool) -> Void = { _, _ in }
    // Fijada: no se esconde sola al sacar el mouse.
    var fijada = false
    // Manda la lista al iPad; al asignarlo se envía el estado actual.
    var emisor: Emisor? {
        didSet { emisor?.cambio(paraIpad, sinVer) }
    }
    private var firma: String?
    private var reloj: Timer?
    private var parpadeoContinuo: Timer?
    // Archivo de la app de Claude de cada sesión sin ver y su última fecha de modificación conocida.
    private var rutasSinVer: [String: (ruta: URL, fecha: Date?)] = [:]
    // No leídas según el Local Storage de Claude (nil: no se pudo leer y manda la heurística) y la firma de sus archivos.
    private var noLeidas: Set<String>?
    private var firmaLeveldb: String?
    // La lista que sale del archivo de avisos, sin las no leídas agregadas al final.
    private var base: [Aviso] = []
    // La fila de la sesión abierta ahora en Claude (ver filaActual); se sigue solo con la barra abierta.
    @Published private(set) var actual: String?
    // Focos e ids de la última lectura completa de las sesiones y la fecha de cada archivo de sesión (por ruta),
    // para releer solo el foco de los que cambian.
    private var sesionesFoco = Sesiones()
    private var fechasFoco: [String: Date] = [:]

    // Lee el archivo al partir (sin parpadear ni abrir la barra) y lo revisa cada segundo por tamaño y fecha.
    func arrancar() {
        revisar(primera: true)
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.revisar(primera: false)
            // Escondida no se mira la carpeta trabajando/: no se ve y así no gasta. Al abrir se lee al tiro.
            if self?.escondida == false { self?.revisarTrabajando() }
            // Una normal que pasa las 12 horas sale sin reiniciar: solo se recalcula en memoria, sin leer nada.
            self?.ordenar()
            if self?.escondida == false { self?.revisarActual() }
            self?.emisor?.tick()
        }
    }

    // Recalcula el orden de pantalla; si cambió, la barra se reacomoda y el iPad recibe la lista nueva.
    // Cambiar de lugar o salir por antigüedad no toca la lista base, así que no cuenta como aviso nuevo.
    private func ordenar() {
        let nuevas = ordenPantalla(avisos + extras, trabajando: trabajando, sinVer: sinVer, ahora: Date())
        guard nuevas != filas else { return }
        filas = nuevas
        tope = nil
        emisor?.cambio(paraIpad, sinVer)
        DispatchQueue.main.async { self.alCambiar(false) }
    }

    // Lee las marcas (solo stat de la carpeta); los títulos de la app se leen solo si pueden cambiar las filas extra.
    private func revisarTrabajando() {
        let nuevo = sesionesTrabajando(leerMarcasTrabajando(), ahora: Date())
        guard nuevo != trabajando else { return }
        trabajando = nuevo
        if !extras.isEmpty || !nuevo.isSubset(of: avisos.map(\.sesion)) { ponerExtras(leerSesiones()) }
    }

    private func ponerExtras(_ sesiones: Sesiones) {
        let nuevas = extrasTrabajando(avisos, trabajando: trabajando, sesiones: sesiones)
        guard nuevas != extras else { return }
        extras = nuevas
        DispatchQueue.main.async { self.alCambiar(false) }
    }

    private func revisar(primera: Bool) {
        let cambioNoLeidas = revisarNoLeidas()
        if noLeidas == nil && !sinVer.isEmpty { revisarFocos() }
        let atributos = try? FileManager.default.attributesOfItem(atPath: rutaAvisos.path)
        let nueva = atributos.map { "\($0[.size] ?? 0)|\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" }
        if !primera && nueva == firma && !cambioNoLeidas { return }
        firma = nueva
        let sesiones = leerSesiones()
        guardarFocos(sesiones)
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
        ponerExtras(sesiones)
        if hayNuevo {
            // Escondida y sin "abrirse sola", la lengüeta avisa hasta que el dueño la abra.
            if escondida && !abrirSola { avisar() } else {
                if escondida { alternar() }
                parpadear()
            }
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

    private func guardarFocos(_ sesiones: Sesiones) {
        sesionesFoco = sesiones
        fechasFoco = archivosSesion()
    }

    // Los archivos local_*.json de las carpetas ya conocidas (también los archivados) con su fecha de modificación,
    // por ruta: solo se lista la carpeta, que trae las fechas en la misma pasada (medio milisegundo con 58).
    private func archivosSesion() -> [String: Date] {
        var archivos: [String: Date] = [:]
        for carpeta in Set(sesionesFoco.rutas.values.map { $0.deletingLastPathComponent().path }) {
            let contenido = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: carpeta), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for archivo in contenido where archivo.lastPathComponent.hasPrefix("local_") && archivo.pathExtension == "json" {
                archivos[archivo.path] = (try? archivo.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            }
        }
        return archivos
    }

    // Cada segundo con la barra abierta: se miran las fechas de los archivos de sesión y se relee el foco solo de los
    // que cambiaron. Si aparece o desaparece un archivo (sesión nueva o borrada) se relee todo, que pasa poco.
    private func revisarActual() {
        let archivos = archivosSesion()
        if Set(archivos.keys) != Set(fechasFoco.keys) {
            guardarFocos(leerSesiones())
        } else {
            for (ruta, fecha) in archivos where fecha != fechasFoco[ruta] {
                fechasFoco[ruta] = fecha
                let foco = leerFoco(ruta: URL(fileURLWithPath: ruta))
                for (id, r) in sesionesFoco.rutas where r.path == ruta { sesionesFoco.focos[id] = foco }
            }
        }
        let nueva = filaActual(filas, focos: sesionesFoco.focos, ids: sesionesFoco.ids)
        if nueva != actual { actual = nueva }
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

    // Parpadeo calmado y continuo de la lengüeta; si ya está parpadeando sigue con el mismo temporizador.
    private func avisar() {
        avisando = true
        guard parpadeoContinuo == nil else { return }
        parpadeoContinuo = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tenue.toggle()
        }
    }

    func alternar() {
        fijada = false
        avisando = false
        parpadeoContinuo?.invalidate()
        parpadeoContinuo = nil
        tenue = false
        escondida.toggle()
        // Los títulos se refrescan al terminar el deslizamiento: leerlos demora y trabaría el comienzo.
        if !escondida {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, !self.escondida else { return }
                let lista = self.conTitulos(self.avisos)
                if lista != self.avisos { self.avisos = lista }
                self.revisarTrabajando()
                self.revisarActual()
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
            Toggle("Abrirse sola con cada aviso", isOn: $estado.abrirSola)
            Divider()
            Button("Salir de Personita") { NSApp.terminate(nil) }
        }
    }

    private var lengueta: some View {
        let marcada = estado.escondida && (!estado.sinVer.isEmpty || estado.avisando)
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
            if estado.visibles.count > 1 {
                Text("Anteriores")
                    .font(.system(size: 11))
                    .foregroundColor(Color(rgb: 0x8d93a0))
                VStack(spacing: 2) {
                    ForEach(estado.visibles.dropFirst(), id: \.sesion) { aviso in
                        Fila(aviso: aviso, sinVer: estado.sinVer.contains(aviso.sesion),
                             trabajando: estadoFila(aviso, trabajando: estado.trabajando, sinVer: estado.sinVer) == .trabajando,
                             actual: estado.actual == aviso.sesion, pausado: estado.escondida, alPasar: { estado.alPasar(aviso, $0) }) { estado.elegir(aviso) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 196, alignment: .topLeading)
        .background(IzquierdaRedondeada(radio: 12).fill(azul))
    }

    private var cuadro: some View {
        let ultimo = estado.filas.first
        // Trabajando va por encima de sin ver (no de esperando).
        let trabajando = ultimo.map { estadoFila($0, trabajando: estado.trabajando, sinVer: estado.sinVer) == .trabajando } ?? false
        let marcado = !trabajando && (ultimo.map { estado.sinVer.contains($0.sesion) } ?? false)
        return Button { if let ultimo { estado.elegir(ultimo) } } label: { contenidoCuadro(marcado: marcado, trabajando: trabajando, ultimo: ultimo) }
            .buttonStyle(Presionable())
            .onHover { dentro in
                encimaCuadro = dentro
                if let ultimo { estado.alPasar(ultimo, dentro) }
            }
    }

    private func contenidoCuadro(marcado: Bool, trabajando: Bool, ultimo: Aviso?) -> some View {
        // Amarillo mientras Claude espera al dueño; el coral de la sesión sin ver va por encima.
        let amarillento = !marcado && ultimo?.esperando == true
        let fondo = marcado ? (encimaCuadro ? coralEncima : coral) : amarillento ? (encimaCuadro ? amarilloEncima : amarillo) : (encimaCuadro ? azulCuadroEncima : azulCuadro)
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ultimo?.esperando == true ? "Te está esperando" : trabajando ? "Trabajando" : "Último terminado")
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
                    Text(ultimo.esperando ? "te está esperando · \(formatoHora.string(from: ultimo.hora))" : trabajando ? "trabajando" : "terminó a las \(formatoHora.string(from: ultimo.hora))")
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
        // Si es la sesión abierta ahora en Claude, la misma rayita de la fila actual.
        .overlay(alignment: .leading) { if let ultimo, estado.actual == ultimo.sesion { Rayita().padding(.vertical, 8) } }
        .opacity(!estado.escondida && estado.tenue ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: estado.tenue)
        .contentShape(Rectangle())
    }
}

struct Fila: View {
    let aviso: Aviso
    let sinVer: Bool
    let trabajando: Bool
    // La sesión abierta ahora en Claude: fondo un poco más claro y rayita a la izquierda, sin cambiar el tamaño.
    let actual: Bool
    let pausado: Bool
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
            if trabajando {
                Latido(pausado: pausado)
            } else if sinVer {
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
            Text(trabajando ? "trabajando" : formatoHora.string(from: aviso.hora))
        }
        .font(.system(size: 12))
        .foregroundColor(aviso.esperando ? azul : celeste)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(aviso.esperando ? (encima ? amarilloEncima : amarillo) : (encima ? azulCuadro : actual ? Color.white.opacity(0.08) : .clear)))
        .overlay(alignment: .leading) { if actual { Rayita().padding(.vertical, 4) } }
        .contentShape(Rectangle())
    }
}

// Rayita blanca vertical de la sesión abierta ahora en Claude; va encima, así no mueve nada.
struct Rayita: View {
    var body: some View {
        Capsule().fill(Color.white).frame(width: 2)
    }
}

// Punto celeste que late (un ciclo cada 2 s) mientras la sesión trabaja; con la barra escondida queda en pausa.
struct Latido: View {
    let pausado: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: pausado)) { linea in
            Circle().fill(celesteTrabajo).frame(width: 6, height: 6)
                .opacity(0.65 + 0.35 * cos(linea.date.timeIntervalSinceReferenceDate * .pi))
        }
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
