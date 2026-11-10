// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
import Foundation

// Local Storage de la app de Claude (LevelDB). Solo se lee, nunca se escribe ni se toca LOCK.
let dirNoLeidas = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/Local Storage/leveldb")

// La única llave que se extrae: la lista de sesiones con el puntito azul de no leído.
private let llaveNoLeidas = Array("_https://claude.ai".utf8) + [0, 1] + Array("epitaxy-unread-v1".utf8)
private let maximo = 16 << 20

private struct Corrupto: Error {}
private typealias Registro = (seq: UInt64, tipo: UInt8, valor: [UInt8])

// Acceso a bytes ajenos, siempre con verificación de límites.
private func byte(_ b: [UInt8], _ i: Int) throws -> UInt8 {
    guard i >= 0, i < b.count else { throw Corrupto() }
    return b[i]
}

private func trozo(_ b: [UInt8], _ i: Int, _ n: Int) throws -> [UInt8] {
    guard i >= 0, n >= 0, i <= b.count - n else { throw Corrupto() }
    return Array(b[i..<i + n])
}

// Entero little-endian de n bytes (hasta 8).
private func entero(_ b: [UInt8], _ i: Int, _ n: Int) throws -> UInt64 {
    try trozo(b, i, n).reversed().reduce(0) { $0 << 8 | UInt64($1) }
}

private func varint(_ b: [UInt8], _ i: inout Int) throws -> Int {
    var r = 0
    for s in stride(from: 0, to: 63, by: 7) {
        let c = try byte(b, i)
        i += 1
        r |= Int(c & 0x7f) << s
        if c < 0x80 { return r }
    }
    throw Corrupto()
}

// Snappy: rechaza largos y offsets fuera de rango y salidas de más de 16 MB.
func descomprimirSnappy(_ b: [UInt8]) -> [UInt8]? {
    var i = 0
    guard let n = try? varint(b, &i), n <= maximo else { return nil }
    var o = [UInt8]()
    o.reserveCapacity(n)
    do {
        while i < b.count {
            let t = b[i]
            i += 1
            var largo: Int, offset: Int
            switch t & 3 {
            case 0:
                largo = Int(t >> 2)
                if largo >= 60 {
                    let nb = largo - 59
                    largo = Int(try entero(b, i, nb))
                    i += nb
                }
                largo += 1
                guard o.count + largo <= n else { return nil }
                o += try trozo(b, i, largo)
                i += largo
                continue
            case 1:
                largo = Int((t >> 2) & 7) + 4
                offset = Int(t >> 5) << 8 | Int(try byte(b, i))
                i += 1
            case 2:
                largo = Int(t >> 2) + 1
                offset = Int(try entero(b, i, 2))
                i += 2
            default:
                largo = Int(t >> 2) + 1
                offset = Int(try entero(b, i, 4))
                i += 4
            }
            guard offset > 0, offset <= o.count, o.count + largo <= n else { return nil }
            for _ in 0..<largo { o.append(o[o.count - offset]) }
        }
    } catch { return nil }
    return o.count == n ? o : nil
}

// Bloque de una tabla según su manija (offset y tamaño en varint); el byte de tipo 1 es snappy.
private func bloque(_ b: [UInt8], _ manija: [UInt8], _ j: inout Int) throws -> [UInt8] {
    let off = try varint(manija, &j), tam = try varint(manija, &j)
    let datos = try trozo(b, off, tam)
    switch try byte(b, off + tam) {
    case 0: return datos
    case 1:
        guard let d = descomprimirSnappy(datos) else { throw Corrupto() }
        return d
    default: throw Corrupto()
    }
}

// Entradas de un bloque: llaves con prefijo compartido y, al final, los reinicios.
private func entradas(_ blk: [UInt8]) throws -> [(llave: [UInt8], valor: [UInt8])] {
    let fin = blk.count - 4 - 4 * Int(try entero(blk, blk.count - 4, 4))
    guard fin >= 0 else { throw Corrupto() }
    var i = 0, llave = [UInt8](), salida: [(llave: [UInt8], valor: [UInt8])] = []
    while i < fin {
        let comun = try varint(blk, &i), propio = try varint(blk, &i), largo = try varint(blk, &i)
        guard comun <= llave.count else { throw Corrupto() }
        llave = Array(llave.prefix(comun)) + (try trozo(blk, i, propio))
        i += propio
        salida.append((llave, try trozo(blk, i, largo)))
        i += largo
    }
    return salida
}

// Tabla .ldb: pie de 48 bytes -> bloque índice -> bloques de datos. Cada llave lleva 8 bytes de secuencia y tipo.
private func tabla(_ b: [UInt8]) throws -> [Registro] {
    guard try entero(b, b.count - 8, 8) == 0xdb4775248b80fb57 else { throw Corrupto() }
    let pie = try trozo(b, b.count - 48, 48)
    var i = 0
    _ = try varint(pie, &i)
    _ = try varint(pie, &i)
    var salida: [Registro] = []
    for (_, manija) in try entradas(try bloque(b, pie, &i)) {
        var j = 0
        for (llave, valor) in try entradas(try bloque(b, manija, &j)) {
            guard llave.count >= 8 else { throw Corrupto() }
            guard Array(llave.dropLast(8)) == llaveNoLeidas else { continue }
            let seq = try entero(llave, llave.count - 8, 8)
            guard seq & 0xff <= 1 else { throw Corrupto() }
            salida.append((seq >> 8, UInt8(seq & 0xff), valor))
        }
    }
    return salida
}

// Registro .log: bloques de 32768 bytes, fragmentos con cabecera de 7 bytes que arman lotes.
// Una cola truncada (Claude a medio escribir) se lee hasta el último fragmento completo.
private func registro(_ b: [UInt8]) throws -> [Registro] {
    var i = 0, acum = [UInt8](), salida: [Registro] = []
    while i + 7 <= b.count {
        let resto = 32768 - i % 32768
        if resto < 7 {
            i += resto
            continue
        }
        let largo = Int(try entero(b, i + 4, 2)), tipo = try byte(b, i + 6)
        if tipo == 0 && largo == 0 { break }
        guard largo <= resto - 7 else { throw Corrupto() }
        guard let d = try? trozo(b, i + 7, largo) else { break }
        i += 7 + largo
        switch tipo {
        case 1, 2: acum = d
        case 3, 4: acum += d
        default: throw Corrupto()
        }
        if tipo == 1 || tipo == 4 { try lote(acum, &salida) }
    }
    return salida
}

// Lote: secuencia (8 bytes), cantidad (4) y registros (tipo, llave y, si es valor, el valor).
private func lote(_ b: [UInt8], _ salida: inout [Registro]) throws {
    let seq = try entero(b, 0, 8), n = try entero(b, 8, 4)
    var j = 12
    for x in 0..<n {
        let tipo = try byte(b, j)
        j += 1
        let kl = try varint(b, &j), llave = try trozo(b, j, kl)
        j += kl
        var valor = [UInt8]()
        if tipo == 1 {
            let vl = try varint(b, &j)
            valor = try trozo(b, j, vl)
            j += vl
        } else if tipo != 0 {
            throw Corrupto()
        }
        if llave == llaveNoLeidas { salida.append((seq &+ x, tipo, valor)) }
    }
}

// Valor: un byte de codificación (1 = Latin-1, 0 = UTF-16LE) y el JSON con unreadIds y explicitUnreadIds.
private func interpretar(_ valor: [UInt8]) -> Set<String>? {
    guard let primero = valor.first else { return nil }
    let resto = Data(valor.dropFirst())
    let codificacion: String.Encoding
    switch primero {
    case 1: codificacion = .isoLatin1
    case 0: codificacion = .utf16LittleEndian
    default: return nil
    }
    guard let texto = String(data: resto, encoding: codificacion),
          let json = try? JSONSerialization.jsonObject(with: Data(texto.utf8)) as? [String: Any],
          let estado = json["state"] as? [String: Any],
          let ids = estado["unreadIds"] as? [Any] else { return nil }
    let todos = ids + (estado["explicitUnreadIds"] as? [Any] ?? [])
    return Set(todos.compactMap { $0 as? String }.filter { calza($0, patronSesion) })
}

// Los ids local_… de las sesiones no leídas según Claude, o nil si no se pudo leer o interpretar.
// Gana el registro de mayor secuencia entre todos los archivos; un borrado más nuevo es el conjunto vacío.
// Un archivo corrupto, truncado o de más de 16 MB se ignora.
func leerNoLeidas(directorio: URL = dirNoLeidas) -> Set<String>? {
    guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: directorio.path) else { return nil }
    var mejor: Registro?
    for nombre in nombres where nombre.hasSuffix(".ldb") || nombre.hasSuffix(".log") {
        let ruta = directorio.appendingPathComponent(nombre)
        guard let tam = (try? FileManager.default.attributesOfItem(atPath: ruta.path))?[.size] as? Int, tam <= maximo,
              let datos = try? Data(contentsOf: ruta), datos.count <= maximo,
              let hallados = try? (nombre.hasSuffix(".ldb") ? tabla([UInt8](datos)) : registro([UInt8](datos))) else { continue }
        for r in hallados where mejor == nil || r.seq > mejor!.seq { mejor = r }
    }
    guard let mejor else { return nil }
    return mejor.tipo == 0 ? [] : interpretar(mejor.valor)
}

// Tamaño y fecha de los .ldb y .log (solo stat), para releer únicamente cuando algo cambió.
func firmaNoLeidas(directorio: URL = dirNoLeidas) -> String? {
    guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: directorio.path) else { return nil }
    return nombres.filter { $0.hasSuffix(".ldb") || $0.hasSuffix(".log") }.sorted().map { nombre in
        let a = try? FileManager.default.attributesOfItem(atPath: directorio.appendingPathComponent(nombre).path)
        return "\(nombre)|\(a?[.size] ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }.joined(separator: ";")
}
