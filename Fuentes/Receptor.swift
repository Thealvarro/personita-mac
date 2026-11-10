// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import Foundation
import Network

let rutaClaveIpad = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/personita-ipad-clave")

// Resultado de analizar una petición completa: la sesión pedida o el código de error a responder.
enum Pedido: Equatable {
    case sesion(String)
    case error(Int)
}

// Recorre siempre todos los bytes, así el tiempo no delata cuántos caracteres calzan.
func igualesTiempoConstante(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    var diferencia: UInt8 = x.count == y.count ? 0 : 1
    for i in 0..<max(x.count, y.count) {
        diferencia |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
    }
    return diferencia == 0
}

// Máximo 20 peticiones en cualquier ventana de 60 s. El reloj es monotónico y se puede inyectar.
struct Limitador {
    private var marcas: [TimeInterval] = []

    mutating func permitir(ahora: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        marcas.removeAll { ahora - $0 >= 60 }
        guard marcas.count < 20 else { return false }
        marcas.append(ahora)
        return true
    }
}

// Analiza los bytes crudos de una petición. nil = todavía faltan bytes.
// Solo vale POST /abrir con Content-Length exacto, X-Clave correcta y cuerpo sesion=<uuid>.
func analizarPedido(_ datos: Data, clave: String) -> Pedido? {
    guard datos.count <= 2048 else { return .error(400) }
    guard let fin = datos.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    guard let cabeza = String(data: datos[..<fin.lowerBound], encoding: .utf8) else { return .error(400) }
    var lineas = cabeza.components(separatedBy: "\r\n")
    guard lineas.removeFirst() == "POST /abrir HTTP/1.1" else { return .error(400) }
    var cabeceras: [String: String] = [:]
    for linea in lineas {
        guard let dosPuntos = linea.firstIndex(of: ":") else { return .error(400) }
        let nombre = linea[..<dosPuntos].lowercased()
        // Una cabecera repetida es ambigua: se rechaza.
        guard cabeceras[nombre] == nil else { return .error(400) }
        cabeceras[nombre] = linea[linea.index(after: dosPuntos)...].trimmingCharacters(in: .whitespaces)
    }
    guard cabeceras["transfer-encoding"] == nil,
          let largo = cabeceras["content-length"].flatMap({ Int($0) }), largo >= 0 else { return .error(400) }
    let cuerpo = datos[fin.upperBound...]
    if cuerpo.count < largo { return nil }
    guard cuerpo.count == largo else { return .error(400) }
    guard let enviada = cabeceras["x-clave"], igualesTiempoConstante(enviada, clave) else { return .error(401) }
    guard let texto = String(data: cuerpo, encoding: .utf8), texto.hasPrefix("sesion=") else { return .error(400) }
    let sesion = String(texto.dropFirst("sesion=".count))
    guard sesion.utf8.count == 36, calza(sesion, patronUUID) else { return .error(400) }
    return .sesion(sesion)
}

private let textos = [200: "ok", 400: "peticion invalida", 401: "no autorizado", 404: "no encontrada", 429: "demasiadas peticiones"]

private func avisar(_ mensaje: String) {
    FileHandle.standardError.write(Data("Personita: \(mensaje)\n".utf8))
}

// Escucha en la red local una sola orden del iPad: abrir una sesión que ya está en la barra.
// Todo corre en el hilo principal.
final class Receptor {
    private let listener: NWListener
    private let clave: String
    private var limitador = Limitador()
    private let avisos: () -> [Aviso]
    private let abrir: (Aviso) -> Void

    // Sin clave, con clave corta o sin poder escuchar, no hay receptor y la barra sigue igual.
    init?(avisos: @escaping () -> [Aviso], abrir: @escaping (Aviso) -> Void, puerto: UInt16 = 8081, rutaClave: URL = rutaClaveIpad) {
        let clave = ((try? String(contentsOf: rutaClave, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Sin clave es lo normal para quien no usa iPad: no hay receptor y no se avisa.
        guard !clave.isEmpty else { return nil }
        guard clave.count >= 16 else {
            avisar("receptor apagado: la clave es muy corta")
            return nil
        }
        guard let puertoNW = NWEndpoint.Port(rawValue: puerto), let listener = try? NWListener(using: .tcp, on: puertoNW) else {
            avisar("receptor apagado: no se pudo escuchar en el puerto \(puerto)")
            return nil
        }
        self.listener = listener
        self.clave = clave
        self.avisos = avisos
        self.abrir = abrir
        listener.stateUpdateHandler = { [weak self] estado in
            guard case .failed(let error) = estado else { return }
            avisar("receptor apagado: \(error)")
            self?.listener.cancel()
        }
        listener.newConnectionHandler = { [weak self] conexion in self?.atender(conexion) }
        listener.start(queue: .main)
    }

    // El límite se cuenta al llegar la conexión, antes de mirar nada. Cada conexión vive máximo 5 s.
    private func atender(_ conexion: NWConnection) {
        let permitido = limitador.permitir()
        conexion.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { conexion.cancel() }
        leer(conexion, Data(), permitido: permitido)
    }

    private func leer(_ conexion: NWConnection, _ previo: Data, permitido: Bool) {
        conexion.receive(minimumIncompleteLength: 1, maximumLength: 2049 - previo.count) { [weak self] datos, _, terminado, error in
            guard let self else { return conexion.cancel() }
            // Pasado el límite se responde 429 sin mirar lo que llegó (se lee una vez para no cortar con RST).
            if !permitido { return self.responder(conexion, 429) }
            if error != nil { return conexion.cancel() }
            let todo = previo + (datos ?? Data())
            switch analizarPedido(todo, clave: self.clave) {
            case nil where terminado: self.responder(conexion, 400)
            case nil: self.leer(conexion, todo, permitido: true)
            case .error(let codigo)?: self.responder(conexion, codigo)
            case .sesion(let sesion)?:
                // La orden solo elige uno de los avisos que la app ya tiene.
                guard let aviso = self.avisos().first(where: { $0.sesion == sesion }) else { return self.responder(conexion, 404) }
                self.abrir(aviso)
                self.responder(conexion, 200)
            }
        }
    }

    private func responder(_ conexion: NWConnection, _ codigo: Int) {
        let texto = textos[codigo] ?? ""
        let http = "HTTP/1.1 \(codigo) \(texto)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(texto.utf8.count)\r\nConnection: close\r\n\r\n\(texto)"
        conexion.send(content: Data(http.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conexion.cancel() })
    }
}
