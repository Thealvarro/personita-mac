// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import AppKit

let dirSesiones = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")

let patronSesion = try! NSRegularExpression(pattern: "^local_[A-Za-z0-9-]{1,64}$")

// Busca la sesión de la app de Claude que corresponde a la sesión del CLI y arma su enlace.
// Solo mira las claves sessionId, cliSessionId, lastAssistantCliSessionId e isArchived (títulos y focos, además, title y lastFocusedAt).
func buscarEnlace(sesion: String, directorio: URL = dirSesiones) -> URL? {
    guard let archivos = FileManager.default.enumerator(at: directorio, includingPropertiesForKeys: nil) else { return nil }
    for case let archivo as URL in archivos where archivo.lastPathComponent.hasPrefix("local_") && archivo.pathExtension == "json" {
        guard let datos = try? Data(contentsOf: archivo),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              json["cliSessionId"] as? String == sesion || json["lastAssistantCliSessionId"] as? String == sesion,
              json["isArchived"] as? Bool != true,
              let id = json["sessionId"] as? String, calza(id, patronSesion) else { continue }
        return URL(string: "claude://code/continue?session=\(id)")
    }
    return nil
}

// De las sesiones no archivadas, por id de sesión del CLI (se usan ambas claves): el título, cuándo se abrió
// por última vez en la app (lastFocusedAt, en milisegundos), la ruta de su archivo y su sessionId.
// Además, por sessionId, el aviso armado desde su archivo (para las no leídas que no están en la lista).
struct Sesiones {
    var titulos: [String: String] = [:]
    var carpetas: [String: String] = [:]
    var focos: [String: Date] = [:]
    var rutas: [String: URL] = [:]
    var ids: [String: String] = [:]
    var porId: [String: Aviso] = [:]
}

func leerSesiones(directorio: URL = dirSesiones) -> Sesiones {
    var sesiones = Sesiones()
    guard let archivos = FileManager.default.enumerator(at: directorio, includingPropertiesForKeys: nil) else { return sesiones }
    for case let archivo as URL in archivos where archivo.lastPathComponent.hasPrefix("local_") && archivo.pathExtension == "json" {
        guard let datos = try? Data(contentsOf: archivo),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              json["isArchived"] as? Bool != true else { continue }
        let titulo = (json["title"] as? String).map { crudo in
            String(String(crudo.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .trimmingCharacters(in: .whitespaces).prefix(60))
        }
        let foco = focoDe(json)
        let carpeta = carpetaDe(json)
        let sessionId = (json["sessionId"] as? String).flatMap { calza($0, patronSesion) ? $0 : nil }
        for clave in ["cliSessionId", "lastAssistantCliSessionId"] {
            guard let id = json[clave] as? String else { continue }
            if let titulo, !titulo.isEmpty { sesiones.titulos[id] = titulo }
            if let carpeta { sesiones.carpetas[id] = carpeta }
            if let foco { sesiones.focos[id] = foco }
            sesiones.rutas[id] = archivo
            if let sessionId { sesiones.ids[id] = sessionId }
        }
        if let sessionId, let aviso = avisoDe(json, titulo: titulo, carpeta: carpeta) { sesiones.porId[sessionId] = aviso }
    }
    return sesiones
}

// Aviso de tipo termino desde el archivo: la carpeta de cwd, cliSessionId y lastTurnEdgeAt (o lastActivityAt), en ms.
private func avisoDe(_ json: [String: Any], titulo: String?, carpeta: String?) -> Aviso? {
    guard let sesion = json["cliSessionId"] as? String, calza(sesion, patronUUID),
          let cwd = json["cwd"] as? String,
          let ms = json["lastTurnEdgeAt"] as? Double ?? json["lastActivityAt"] as? Double else { return nil }
    let proyecto = String(String((cwd as NSString).lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(40))
    guard !proyecto.isEmpty else { return nil }
    return Aviso(proyecto: proyecto, sesion: sesion, hora: Date(timeIntervalSince1970: ms / 1000), titulo: titulo?.isEmpty == false ? titulo : nil, carpeta: carpeta)
}

// Último componente del cwd, sin caracteres de control y cortado a 40.
private func carpetaDe(_ json: [String: Any]) -> String? {
    guard let cwd = json["cwd"] as? String else { return nil }
    let limpia = String(String((cwd as NSString).lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(40))
    return limpia.isEmpty ? nil : limpia
}

private func focoDe(_ json: [String: Any]) -> Date? {
    (json["lastFocusedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
}

// Vuelve a leer el foco de un solo archivo (para saber si el dueño ya abrió esa sesión).
func leerFoco(ruta: URL) -> Date? {
    guard let datos = try? Data(contentsOf: ruta),
          let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
          json["isArchived"] as? Bool != true else { return nil }
    return focoDe(json)
}

func abrirSesion(_ aviso: Aviso) {
    if let enlace = buscarEnlace(sesion: aviso.sesion) {
        NSWorkspace.shared.open(enlace)
    } else {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Claude.app"), configuration: NSWorkspace.OpenConfiguration())
    }
}
