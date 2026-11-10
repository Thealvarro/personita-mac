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

// El aviso nuevo sube arriba; si la sesión ya estaba, su fila anterior se elimina. Máximo 6.
func agregar(_ nuevo: Aviso, a lista: [Aviso]) -> [Aviso] {
    Array(([nuevo] + lista.filter { $0.sesion != nuevo.sesion }).prefix(6))
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
