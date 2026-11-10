// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import Foundation
import Network

// Cuerpo JSON del estado completo: los 12 primeros avisos, en el orden en que se muestran.
func cuerpoEstado(avisos: [Aviso], sinVer: Set<String>, nuevo: Bool) -> Data {
    let lista = avisos.prefix(12).map { a -> [String: Any] in
        var d: [String: Any] = ["nombre": a.nombre, "sesion": a.sesion, "hora": Int(a.hora.timeIntervalSince1970), "esperando": a.esperando, "sinVer": sinVer.contains(a.sesion)]
        if let carpeta = a.carpetaVisible { d["carpeta"] = carpeta }
        return d
    }
    return (try? JSONSerialization.data(withJSONObject: ["nuevo": nuevo, "avisos": lista] as [String: Any])) ?? Data()
}

// Archivo opcional con el nombre o IP del iPad, una línea.
let rutaArchivoIpad = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/personita-mac/ipad")
private let patronHost = try! NSRegularExpression(pattern: "^[A-Za-z0-9.-]{1,253}$")

private func avisarEmisor(_ mensaje: String) {
    FileHandle.standardError.write(Data("Personita: \(mensaje)\n".utf8))
}

// Le manda su lista al iPad cada vez que cambia, más un latido cada 60 s. Todo corre en el hilo principal.
final class Emisor {
    private let host: NWEndpoint.Host
    private let puerto: NWEndpoint.Port
    private let destino: String
    private let clave: String
    private let reloj: () -> TimeInterval
    // Para pruebas: avisa si cada envío llegó (true) o falló (false).
    var alResponder: (Bool) -> Void = { _ in }
    private var avisos: [Aviso] = []
    private var sinVer: Set<String> = []
    private var nuevo = false
    private var sucio = false
    private var programado = false
    private var enVuelo = false
    private var fallos = 0
    private var reintentoEn: TimeInterval?
    private var ultimoIntento = -TimeInterval.infinity

    // Sin archivo del iPad (lo normal si no se usa iPad) o con host inválido, no hay emisor y la barra sigue igual.
    // Con clave ausente o corta tampoco. El host se puede pasar directo (pruebas) o se lee de rutaIpad.
    init?(host: String? = nil, puerto: UInt16 = 8080, rutaIpad: URL = rutaArchivoIpad, rutaClave: URL = rutaClaveIpad,
          reloj: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        let host = (host ?? ((try? String(contentsOf: rutaIpad, encoding: .utf8)) ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        guard calza(host, patronHost) else {
            avisarEmisor("emisor apagado: el nombre del iPad no es válido")
            return nil
        }
        let clave = ((try? String(contentsOf: rutaClave, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard clave.count >= 16, let puertoNW = NWEndpoint.Port(rawValue: puerto) else {
            avisarEmisor("emisor apagado: falta la clave o es muy corta")
            return nil
        }
        self.host = NWEndpoint.Host(host)
        self.puerto = puertoNW
        self.destino = "\(host):\(puerto)"
        self.clave = clave
        self.reloj = reloj
    }

    // Se llama justo antes del cambio que trae un aviso nuevo.
    func marcarNuevo() { nuevo = true }

    // La lista cambió: se manda lo más reciente (los cambios del mismo instante se juntan en un envío).
    func cambio(_ avisos: [Aviso], _ sinVer: Set<String>) {
        self.avisos = avisos
        self.sinVer = sinVer
        sucio = true
        fallos = 0
        reintentoEn = nil
        guard !programado else { return }
        programado = true
        DispatchQueue.main.async { [weak self] in
            self?.programado = false
            self?.enviarSiPuede()
        }
    }

    // Cada segundo: reintentos a los 5 s y latido a los 60 s del último intento.
    func tick() {
        guard !enVuelo else { return }
        let ahora = reloj()
        if let r = reintentoEn {
            if ahora >= r { enviar() }
        } else if ahora - ultimoIntento >= 60 {
            fallos = 0
            enviar()
        }
    }

    private func enviarSiPuede() {
        if !enVuelo && sucio { enviar() }
    }

    private func enviar() {
        sucio = false
        reintentoEn = nil
        enVuelo = true
        ultimoIntento = reloj()
        let llevaNuevo = nuevo
        nuevo = false
        conectar(cuerpoEstado(avisos: avisos, sinVer: sinVer, nuevo: llevaNuevo)) { [weak self] ok in
            guard let self else { return }
            self.enVuelo = false
            if !ok {
                self.fallos += 1
                // Un envío con nuevo que falla lo mantiene en sus reintentos; agotados, se deja.
                if self.fallos <= 3 {
                    self.nuevo = self.nuevo || llevaNuevo
                    self.reintentoEn = self.reloj() + 5
                }
            } else {
                self.fallos = 0
            }
            self.alResponder(ok)
            self.enviarSiPuede()
        }
    }

    // POST /estado; solo importa la línea de estado de la respuesta (200 = entregado). Máximo 4 s.
    private func conectar(_ cuerpo: Data, _ fin: @escaping (Bool) -> Void) {
        let parametros = NWParameters.tcp
        // Solo IPv4: el iPad saca la IPv4 del Mac desde el origen de esta conexión.
        (parametros.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conexion = NWConnection(host: host, port: puerto, using: parametros)
        var hecho = false
        func cerrar(_ ok: Bool) {
            guard !hecho else { return }
            hecho = true
            conexion.cancel()
            fin(ok)
        }
        func leer(_ previo: Data) {
            conexion.receive(minimumIncompleteLength: 1, maximumLength: 1024 - previo.count) { datos, _, terminado, error in
                let todo = previo + (datos ?? Data())
                if let finLinea = todo.range(of: Data("\r\n".utf8)) {
                    let partes = String(decoding: todo[..<finLinea.lowerBound], as: UTF8.self).split(separator: " ")
                    cerrar(partes.count >= 2 && partes[0].hasPrefix("HTTP/1.") && partes[1] == "200")
                } else if error != nil || terminado || todo.count >= 1024 {
                    cerrar(false)
                } else {
                    leer(todo)
                }
            }
        }
        let cabeza = "POST /estado HTTP/1.1\r\nHost: \(destino)\r\nX-Clave: \(clave)\r\nContent-Type: application/json\r\nContent-Length: \(cuerpo.count)\r\nConnection: close\r\n\r\n"
        conexion.stateUpdateHandler = { estado in
            switch estado {
            case .ready:
                conexion.send(content: Data(cabeza.utf8) + cuerpo, completion: .contentProcessed { error in
                    if error != nil { cerrar(false) } else { leer(Data()) }
                })
            case .failed, .waiting:
                cerrar(false)
            default:
                break
            }
        }
        conexion.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { cerrar(false) }
    }
}
