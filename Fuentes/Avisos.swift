// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import Foundation

// Tipo de línea: terminó el turno, quedó esperando al dueño, o el dueño ya respondió.
enum Tipo: String {
    case termino, espera, respondio
}

// Un aviso: un proyecto cuya sesión de Claude Code terminó o está esperando.
struct Aviso: Equatable {
    let proyecto: String
    let sesion: String
    let hora: Date
    var tipo: Tipo = .termino
    var titulo: String? = nil
    var carpeta: String? = nil
    var esperando: Bool { tipo == .espera }
    // Lo que se muestra: el título de la sesión si se conoce, si no la carpeta.
    var nombre: String { titulo ?? proyecto }
    // La carpeta chica de arriba: solo con título y si no repite lo que ya se muestra.
    var carpetaVisible: String? {
        guard titulo != nil, let carpeta, !carpeta.isEmpty, carpeta != nombre else { return nil }
        return carpeta
    }
}

// PERSONITA_AVISOS cambia la ruta del archivo (solo para pruebas).
let rutaAvisos = ProcessInfo.processInfo.environment["PERSONITA_AVISOS"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/personita-mac/avisos.jsonl")

let patronUUID = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

func calza(_ texto: String, _ patron: NSRegularExpression) -> Bool {
    patron.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)) != nil
}

// Lee el archivo línea por línea, en orden; las líneas inválidas se ignoran.
func leerAvisos(ruta: URL = rutaAvisos) -> [Aviso] {
    guard let texto = try? String(contentsOf: ruta, encoding: .utf8) else { return [] }
    return texto.split(separator: "\n").compactMap { linea in
        guard let datos = linea.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let sesion = json["sesion"] as? String, calza(sesion, patronUUID),
              let crudo = json["proyecto"] as? String,
              let hora = json["hora"] as? Double,
              // Las líneas sin tipo (formato viejo) valen como termino.
              let tipo = Tipo(rawValue: json["tipo"] as? String ?? "termino") else { return nil }
        let proyecto = String(String(crudo.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(40))
        guard !proyecto.isEmpty else { return nil }
        return Aviso(proyecto: proyecto, sesion: sesion, hora: Date(timeIntervalSince1970: hora), tipo: tipo)
    }
}

// El aviso nuevo sube arriba; si la sesión ya estaba, su fila anterior se elimina. Máximo 30: el recorte
// de lo que se ve lo hace ordenPantalla, así una activa antigua no se pierde.
func agregar(_ nuevo: Aviso, a lista: [Aviso]) -> [Aviso] {
    Array(([nuevo] + lista.filter { $0.sesion != nuevo.sesion }).prefix(30))
}

// Un respondio apaga el esperando de su sesión sin moverla ni cambiarle la hora.
func reconstruir(_ avisos: [Aviso]) -> [Aviso] {
    avisos.reduce([]) { lista, aviso in
        guard aviso.tipo == .respondio else { return agregar(aviso, a: lista) }
        return lista.map { $0.sesion == aviso.sesion && $0.esperando ? Aviso(proyecto: $0.proyecto, sesion: $0.sesion, hora: $0.hora, tipo: .respondio) : $0 }
    }
}

// Hay aviso nuevo solo si cambió quién está primero o su hora, no si solo cambió esperando.
func hayAvisoNuevo(antes: [Aviso], despues: [Aviso]) -> Bool {
    guard let nuevo = despues.first else { return false }
    guard let viejo = antes.first else { return true }
    return nuevo.proyecto != viejo.proyecto || nuevo.sesion != viejo.sesion || nuevo.hora != viejo.hora
}

// Sin ver: cuando la sesión terminó el dueño ya estaba mirando otra (otra se enfocó entre su foco y la hora del aviso).
// Si estaba abierta al terminar, o no tiene foco, cuenta como vista.
func estaSinVer(foco: Date?, hora: Date, focos: [Date]) -> Bool {
    guard let foco, foco < hora else { return false }
    return focos.contains { foco < $0 && $0 < hora }
}

// Las sesiones sin ver tras un cambio de la lista: cada aviso nuevo (al partir, todos) se evalúa con la regla,
// un respondio saca a su sesión, y la que sale de la lista también.
func sinVerTras(_ sinVer: Set<String>, antes: [Aviso], despues: [Aviso], focos: [String: Date]) -> Set<String> {
    var nuevo = sinVer
    for aviso in despues {
        if aviso.tipo == .respondio {
            nuevo.remove(aviso.sesion)
        } else if antes.first(where: { $0.sesion == aviso.sesion })?.hora != aviso.hora {
            if estaSinVer(foco: focos[aviso.sesion], hora: aviso.hora, focos: Array(focos.values)) {
                nuevo.insert(aviso.sesion)
            } else {
                nuevo.remove(aviso.sesion)
            }
        }
    }
    return nuevo.intersection(despues.map(\.sesion))
}

// Con el conjunto de no leídas de Claude, las que no están en la lista van al final, de más nueva a más vieja.
// Sin conjunto (nil), la lista queda igual.
func conNoLeidas(_ lista: [Aviso], noLeidas: Set<String>?, sesiones: Sesiones) -> [Aviso] {
    guard let noLeidas else { return lista }
    let presentes = Set(lista.compactMap { sesiones.ids[$0.sesion] })
    var vistas = Set(lista.map(\.sesion))
    let extra = noLeidas.subtracting(presentes).compactMap { sesiones.porId[$0] }.sorted { $0.hora > $1.hora }
    return lista + extra.filter { vistas.insert($0.sesion).inserted }
}

// Con el conjunto de no leídas de Claude, sin ver son las de la lista que están en él; sin conjunto, la heurística de focos.
func calcularSinVer(_ sinVer: Set<String>, noLeidas: Set<String>?, antes: [Aviso], despues: [Aviso], sesiones: Sesiones) -> Set<String> {
    guard let noLeidas else { return sinVerTras(sinVer, antes: antes, despues: despues, focos: sesiones.focos) }
    return Set(despues.filter { sesiones.ids[$0.sesion].map(noLeidas.contains) ?? false }.map(\.sesion))
}

// Sesiones trabajando: el hook deja un archivo vacío por sesión en trabajando/ y le sube la fecha en cada paso.
// PERSONITA_TRABAJANDO cambia la carpeta (solo para pruebas).
let dirTrabajando = ProcessInfo.processInfo.environment["PERSONITA_TRABAJANDO"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/personita-mac/trabajando")

// Una marca sin tocar por 15 minutos ya no cuenta (si se cortó con Esc nunca llega stop).
let vigenciaTrabajando: TimeInterval = 15 * 60

// Las marcas con su fecha de modificación; solo nombres con forma de UUID.
func leerMarcasTrabajando(directorio: URL = dirTrabajando) -> [String: Date] {
    guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: directorio.path) else { return [:] }
    var marcas: [String: Date] = [:]
    for nombre in nombres where calza(nombre, patronUUID) {
        if let fecha = (try? FileManager.default.attributesOfItem(atPath: directorio.appendingPathComponent(nombre).path))?[.modificationDate] as? Date {
            marcas[nombre] = fecha
        }
    }
    return marcas
}

// Trabajando: marca con menos de 15 minutos.
func sesionesTrabajando(_ marcas: [String: Date], ahora: Date) -> Set<String> {
    Set(marcas.filter { ahora.timeIntervalSince($0.value) < vigenciaTrabajando }.keys)
}

// Las que trabajan y no están en la lista van al final, de más nueva a más vieja, armadas desde su archivo
// de la app de Claude; si no se puede resolver, se omiten.
func extrasTrabajando(_ lista: [Aviso], trabajando: Set<String>, sesiones: Sesiones) -> [Aviso] {
    // Una sesión de la app puede tener dos ids del CLI: si ya está en la lista (o ya se agregó), no se repite.
    var vistas = Set(lista.compactMap { sesiones.ids[$0.sesion] })
    let extra = trabajando.subtracting(lista.map(\.sesion)).compactMap { id -> (sessionId: String, aviso: Aviso)? in
        guard let sessionId = sesiones.ids[id], let a = sesiones.porId[sessionId] else { return nil }
        return (sessionId, Aviso(proyecto: a.proyecto, sesion: id, hora: a.hora, titulo: a.titulo, carpeta: a.carpeta))
    }.sorted { $0.aviso.hora != $1.aviso.hora ? $0.aviso.hora > $1.aviso.hora : $0.aviso.sesion < $1.aviso.sesion }
    return extra.filter { vistas.insert($0.sessionId).inserted }.map(\.aviso)
}

// Cómo se pinta una fila: esperando > trabajando > sin ver > normal.
enum EstadoFila: Equatable {
    case esperando, trabajando, sinVer, normal
}

func estadoFila(_ aviso: Aviso, trabajando: Set<String>, sinVer: Set<String>) -> EstadoFila {
    if aviso.esperando { return .esperando }
    if trabajando.contains(aviso.sesion) { return .trabajando }
    return sinVer.contains(aviso.sesion) ? .sinVer : .normal
}

// Lo que se ve: las activas (esperando, trabajando o sin ver) siempre y sin tope; después las normales, que solo
// completan hasta 6 filas y salen si su último aviso tiene más de 12 horas. Cada grupo, de más nueva a más vieja.
func ordenPantalla(_ lista: [Aviso], trabajando: Set<String>, sinVer: Set<String>, ahora: Date) -> [Aviso] {
    // Orden estable por hora: a igual hora se respeta el orden de la lista.
    let porHora = lista.enumerated().sorted { $0.element.hora != $1.element.hora ? $0.element.hora > $1.element.hora : $0.offset < $1.offset }.map(\.element)
    let activas = porHora.filter { estadoFila($0, trabajando: trabajando, sinVer: sinVer) != .normal }
    let normales = porHora.filter { estadoFila($0, trabajando: trabajando, sinVer: sinVer) == .normal && ahora.timeIntervalSince($0.hora) <= 12 * 3600 }
    return activas + normales.prefix(max(0, 6 - activas.count))
}

// La fila de la sesión que el dueño tiene abierta en Claude: la de foco (lastFocusedAt) más reciente. Los focos
// e ids vienen por id del CLI; los dos ids de una misma sesión de la app cuentan como una. Si esa sesión no está
// en las filas, si dos sesiones empatan o si no hay focos, ninguna.
func filaActual(_ filas: [Aviso], focos: [String: Date], ids: [String: String]) -> String? {
    var porSesion: [String: Date] = [:]
    for (id, foco) in focos { porSesion[ids[id] ?? id] = max(porSesion[ids[id] ?? id] ?? foco, foco) }
    guard let mayor = porSesion.values.max() else { return nil }
    let primeras = porSesion.filter { $0.value == mayor }
    guard primeras.count == 1, let actual = primeras.first?.key else { return nil }
    return filas.first { (ids[$0.sesion] ?? $0.sesion) == actual }?.sesion
}
