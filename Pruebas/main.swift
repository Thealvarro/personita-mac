// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
// Pruebas de lógica: se compila junto a Avisos.swift, AbrirSesion.swift, Receptor.swift, Emisor.swift y NoLeidas.swift (ver Pruebas/probar.sh).
// Uso: Pruebas <carpeta temporal>
import Foundation
import Network

let base = URL(fileURLWithPath: CommandLine.arguments[1])
// Puerto alto bajo el rango efímero (49152+) y comprobado como libre: uno al azar podía estar ocupado y la prueba de red fallaba.
var puertosUsados: Set<UInt16> = []
func puertoLibre() -> UInt16 {
    while true {
        let p = UInt16.random(in: 30000...45000)
        guard !puertosUsados.contains(p) else { continue }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var dir = sockaddr_in()
        dir.sin_family = sa_family_t(AF_INET)
        dir.sin_port = p.bigEndian
        dir.sin_addr.s_addr = INADDR_ANY
        let ok = withUnsafePointer(to: &dir) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
        if ok { puertosUsados.insert(p); return p }
    }
}
var fallas = 0
func revisar(_ ok: Bool, _ nombre: String) {
    print(ok ? "ok    \(nombre)" : "FALLA \(nombre)")
    if !ok { fallas += 1 }
}

let uA = "11111111-1111-4111-8111-111111111111", uB = "22222222-2222-4222-8222-222222222222"
func linea(_ p: String, _ s: String, _ h: Int) -> String { "{\"proyecto\":\"\(p)\",\"sesion\":\"\(s)\",\"cwd\":\"/x/\(p)\",\"hora\":\(h)}" }
func escribir(_ lineas: [String]) -> URL {
    let ruta = base.appendingPathComponent("avisos.jsonl")
    try! (lineas.joined(separator: "\n") + "\n").write(to: ruta, atomically: true, encoding: .utf8)
    return ruta
}

// (a) A, B, A -> [A, B] con la hora nueva de A
let a = reconstruir(leerAvisos(ruta: escribir([linea("A", uA, 100), linea("B", uB, 200), linea("A", uA, 300)])))
revisar(a.map(\.proyecto) == ["A", "B"] && a[0].hora.timeIntervalSince1970 == 300, "A, B, A -> [A, B] con hora 300 para A")

// (b) máximo 30 al leer (el recorte visible lo hace ordenPantalla)
let b = reconstruir(leerAvisos(ruta: escribir((1...35).map { linea("P\($0)", String(format: "00000000-0000-4000-8000-%012d", $0), $0) })))
revisar(b.count == 30 && b.first?.proyecto == "P35" && b.last?.proyecto == "P6", "máximo 30, el más nuevo primero")

// (c) líneas inválidas ignoradas
let c = leerAvisos(ruta: escribir([
    "esto no es json", "{}", linea("malo", "no-es-uuid", 1),
    "{\"proyecto\":\"\",\"sesion\":\"\(uA)\",\"hora\":1}",
    "{\"proyecto\":\"sin hora\",\"sesion\":\"\(uA)\"}",
    linea("bueno", uB, 5), "{\"proyecto\":",
]))
revisar(c.map(\.proyecto) == ["bueno"], "líneas inválidas ignoradas")

// (d) búsqueda de sesión en un directorio de sesiones falso
let dir = base.appendingPathComponent("sesiones/cuenta/org")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
func sesion(_ nombre: String, _ json: [String: Any]) {
    try! JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent(nombre))
}
let uC = "33333333-3333-4333-8333-333333333333", uD = "44444444-4444-4444-8444-444444444444"
sesion("local_archivada.json", ["sessionId": "local_archivada", "cliSessionId": uA, "isArchived": true])
sesion("local_buena.json", ["sessionId": "local_abc-123", "cliSessionId": "otra", "lastAssistantCliSessionId": uA, "isArchived": false])
sesion("local_mala.json", ["sessionId": "local_x;open -a Calculator", "cliSessionId": uC])
sesion("local_cli.json", ["sessionId": "local_def-456", "cliSessionId": uD])
let raiz = base.appendingPathComponent("sesiones")
revisar(buscarEnlace(sesion: uA, directorio: raiz)?.absoluteString == "claude://code/continue?session=local_abc-123", "coincide por lastAssistantCliSessionId, salta la archivada")
revisar(buscarEnlace(sesion: uD, directorio: raiz)?.absoluteString == "claude://code/continue?session=local_def-456", "coincide por cliSessionId")
revisar(buscarEnlace(sesion: uC, directorio: raiz) == nil, "sessionId inválido -> sin enlace")
revisar(buscarEnlace(sesion: uB, directorio: raiz) == nil, "sin coincidencia -> sin enlace")

// Una fila por sesión
let dosCarpeta = reconstruir(leerAvisos(ruta: escribir([linea("X", uA, 100), linea("X", uB, 200)])))
revisar(dosCarpeta.map(\.sesion) == [uB, uA], "dos sesiones de la misma carpeta -> dos filas")
let mismaSesion = reconstruir(leerAvisos(ruta: escribir([linea("X", uA, 100), linea("Y", uB, 150), linea("Z", uA, 200)])))
revisar(mismaSesion.map(\.proyecto) == ["Z", "Y"] && mismaSesion[0].hora.timeIntervalSince1970 == 200, "misma sesión con dos proyectos -> una fila con el último")

// Títulos de sesiones
let dirT = base.appendingPathComponent("titulos/cuenta/org")
try! FileManager.default.createDirectory(at: dirT, withIntermediateDirectories: true)
func sesionT(_ nombre: String, _ json: [String: Any]) {
    try! JSONSerialization.data(withJSONObject: json).write(to: dirT.appendingPathComponent(nombre))
}
sesionT("local_1.json", ["sessionId": "local_1", "cliSessionId": uA, "title": "  Arreglar el login  "])
sesionT("local_2.json", ["sessionId": "local_2", "cliSessionId": "otra", "lastAssistantCliSessionId": uB, "title": "Subir facturas"])
sesionT("local_3.json", ["sessionId": "local_3", "cliSessionId": uC, "isArchived": true, "title": "Archivada"])
sesionT("local_4.json", ["sessionId": "local_4", "cliSessionId": uD, "title": "\u{7}\n \t"])
sesionT("local_5.json", ["sessionId": "local_5", "cliSessionId": "larga", "title": String(repeating: "x", count: 100)])
let titulos = leerSesiones(directorio: base.appendingPathComponent("titulos")).titulos
revisar(titulos[uA] == "Arreglar el login", "título por cliSessionId, sin espacios al borde")
revisar(titulos[uB] == "Subir facturas" && titulos["otra"] == "Subir facturas", "título por lastAssistantCliSessionId")
revisar(titulos[uC] == nil, "sesión archivada ignorada")
revisar(titulos[uD] == nil, "título solo con caracteres de control ignorado")
revisar(titulos["larga"]?.count == 60, "título largo recortado a 60")
revisar(Aviso(proyecto: "P", sesion: uA, hora: Date()).nombre == "P" && Aviso(proyecto: "P", sesion: uA, hora: Date(), titulo: "T").nombre == "T", "nombre cae al proyecto sin título")

// Carpeta chica: de qué proyecto es la sesión
sesionT("local_6.json", ["sessionId": "local_6", "cliSessionId": "conCwd", "title": "T", "cwd": "/Users/x/Documents/instagram"])
sesionT("local_7.json", ["sessionId": "local_7", "cliSessionId": "cwdLargo", "title": "T", "cwd": "/a/\u{7}" + String(repeating: "ñ", count: 60)])
sesionT("local_8.json", ["sessionId": "local_8", "cliSessionId": "archCwd", "isArchived": true, "title": "T", "cwd": "/a/b"])
let carpetas = leerSesiones(directorio: base.appendingPathComponent("titulos")).carpetas
revisar(carpetas["conCwd"] == "instagram", "carpeta: último componente del cwd")
revisar(carpetas["cwdLargo"] == String(repeating: "ñ", count: 40), "carpeta: sin control y cortada a 40")
revisar(carpetas["archCwd"] == nil && carpetas[uA] == nil, "carpeta: archivada o sin cwd no hay")
revisar(Aviso(proyecto: "p", sesion: uA, hora: Date(), titulo: "T", carpeta: "instagram").carpetaVisible == "instagram", "carpetaVisible: con título y carpeta distinta se ve")
revisar(Aviso(proyecto: "p", sesion: uA, hora: Date(), carpeta: "instagram").carpetaVisible == nil, "carpetaVisible: sin título es nil")
revisar(Aviso(proyecto: "p", sesion: uA, hora: Date(), titulo: "T", carpeta: "T").carpetaVisible == nil, "carpetaVisible: carpeta igual al nombre es nil")
revisar(Aviso(proyecto: "p", sesion: uA, hora: Date(), titulo: "T").carpetaVisible == nil, "carpetaVisible: sin carpeta es nil")
let con1 = [Aviso(proyecto: "p", sesion: uA, hora: h(10), titulo: "T", carpeta: "uno")]
revisar(!hayAvisoNuevo(antes: con1, despues: [Aviso(proyecto: "p", sesion: uA, hora: h(10), titulo: "T", carpeta: "dos")]), "cambio de carpeta no es aviso nuevo")

// Tipos: espera, respondio, termino
func lineaT(_ p: String, _ s: String, _ h: Int, _ t: String) -> String { "{\"proyecto\":\"\(p)\",\"sesion\":\"\(s)\",\"cwd\":\"/x/\(p)\",\"hora\":\(h),\"tipo\":\"\(t)\"}" }
let e = reconstruir(leerAvisos(ruta: escribir([lineaT("A", uA, 100, "termino"), lineaT("B", uB, 200, "espera")])))
revisar(e.map(\.proyecto) == ["B", "A"] && e[0].esperando && !e[1].esperando, "espera marca esperando")
let r = reconstruir(leerAvisos(ruta: escribir([lineaT("B", uB, 100, "espera"), lineaT("A", uA, 200, "termino"), lineaT("B", uB, 300, "respondio")])))
revisar(r.map(\.proyecto) == ["A", "B"] && !r[1].esperando && r[1].hora.timeIntervalSince1970 == 100, "respondio apaga sin mover ni cambiar la hora")
let o = reconstruir(leerAvisos(ruta: escribir([lineaT("B", uB, 100, "espera"), lineaT("A", uA, 200, "respondio")])))
revisar(o.map(\.proyecto) == ["B"] && o[0].esperando, "respondio de otra sesión no afecta")
let t = reconstruir(leerAvisos(ruta: escribir([lineaT("B", uB, 100, "espera"), lineaT("A", uA, 200, "termino"), lineaT("B", uB, 300, "termino")])))
revisar(t.map(\.proyecto) == ["B", "A"] && !t[0].esperando && t[0].hora.timeIntervalSince1970 == 300, "termino posterior apaga y sube")
let v = leerAvisos(ruta: escribir([linea("A", uA, 100), lineaT("B", uB, 200, "otro")]))
revisar(v.map(\.proyecto) == ["A"] && v[0].tipo == .termino, "línea sin tipo vale como termino; tipo desconocido ignorado")
revisar(!hayAvisoNuevo(antes: e, despues: [Aviso(proyecto: "B", sesion: uB, hora: e[0].hora, tipo: .respondio)] + e.dropFirst()), "cambio solo en esperando no es aviso nuevo")
revisar(hayAvisoNuevo(antes: r, despues: t) && hayAvisoNuevo(antes: [], despues: e) && !hayAvisoNuevo(antes: e, despues: []), "cambio de primero sí es aviso nuevo")

var conTitulo = e
conTitulo[0].titulo = "Otro título"
revisar(!hayAvisoNuevo(antes: e, despues: conTitulo), "cambio solo de título no es aviso nuevo")

// Sin ver: regla
func h(_ x: Double) -> Date { Date(timeIntervalSince1970: x) }
revisar(!estaSinVer(foco: h(100), hora: h(200), focos: [h(100), h(50)]), "S abierta al terminar -> vista")
revisar(estaSinVer(foco: h(100), hora: h(200), focos: [h(100), h(150)]), "otra sesión enfocada entre medio -> sin ver")
revisar(!estaSinVer(foco: h(250), hora: h(200), focos: [h(250), h(150)]), "S enfocada después de T -> vista")
revisar(!estaSinVer(foco: nil, hora: h(200), focos: [h(150)]), "sin foco -> vista")
revisar(!estaSinVer(foco: h(100), hora: h(200), focos: [h(100), h(200), h(300)]), "otra enfocada en T o después no cuenta")

// Sin ver: focos en el formato real (lastFocusedAt en milisegundos, número)
let dirF = base.appendingPathComponent("focos/cuenta/org")
try! FileManager.default.createDirectory(at: dirF, withIntermediateDirectories: true)
func sesionF(_ nombre: String, _ json: [String: Any]) {
    try! JSONSerialization.data(withJSONObject: json).write(to: dirF.appendingPathComponent(nombre))
}
sesionF("local_f1.json", ["sessionId": "local_f1", "cliSessionId": uA, "lastFocusedAt": 1794327307497, "title": "Con foco"])
sesionF("local_f2.json", ["sessionId": "local_f2", "cliSessionId": "otra", "lastAssistantCliSessionId": uB, "lastFocusedAt": 1794327400000])
sesionF("local_f3.json", ["sessionId": "local_f3", "cliSessionId": uC, "title": "Sin foco"])
sesionF("local_f4.json", ["sessionId": "local_f4", "cliSessionId": uD, "isArchived": true, "lastFocusedAt": 1794327500000])
let sesF = leerSesiones(directorio: base.appendingPathComponent("focos"))
revisar(sesF.focos[uA] == h(1794327307.497) && sesF.focos[uB] == h(1794327400) && sesF.focos["otra"] == h(1794327400), "foco en milisegundos, por ambas claves")
revisar(sesF.focos[uC] == nil && sesF.titulos[uC] == "Sin foco" && sesF.titulos[uB] == nil, "sin foco o sin título, lo otro igual se lee")
revisar(sesF.focos[uD] == nil && sesF.rutas[uD] == nil, "archivada fuera")
revisar(sesF.rutas[uA]?.lastPathComponent == "local_f1.json" && leerFoco(ruta: sesF.rutas[uA]!) == h(1794327307.497), "ruta guardada y foco releído de un archivo")
revisar(leerFoco(ruta: dirF.appendingPathComponent("no-existe.json")) == nil, "sin archivo -> sin foco")

// Sin ver: cómo cambia el conjunto con la lista
let focos = [uA: h(100), uB: h(150), uC: h(110)]
let lista1 = [Aviso(proyecto: "A", sesion: uA, hora: h(200)), Aviso(proyecto: "B", sesion: uB, hora: h(160)), Aviso(proyecto: "C", sesion: uC, hora: h(160))]
let alPartir = sinVerTras([], antes: [], despues: lista1, focos: focos)
revisar(alPartir == [uA, uC], "al partir se evalúa cada aviso")
revisar(sinVerTras(alPartir, antes: lista1, despues: lista1, focos: [uA: h(300), uB: h(150), uC: h(110)]) == alPartir, "sin aviso nuevo no se reevalúa")
let lista2 = [Aviso(proyecto: "B", sesion: uB, hora: h(400))] + lista1.filter { $0.sesion != uB }
revisar(sinVerTras(alPartir, antes: lista1, despues: lista2, focos: [uA: h(300), uB: h(150), uC: h(110)]) == [uA, uB, uC], "aviso nuevo con otra enfocada entre medio entra")
var lista3 = lista1
lista3[0].tipo = .respondio
revisar(sinVerTras(alPartir, antes: lista1, despues: lista3, focos: focos) == [uC], "respondio la saca")
revisar(sinVerTras(alPartir, antes: lista1, despues: Array(lista1.prefix(2)), focos: focos) == [uA], "la que sale de la lista sale")
revisar(sinVerTras([uA], antes: lista1, despues: [Aviso(proyecto: "A", sesion: uA, hora: h(500))] + lista1.dropFirst(), focos: [uA: h(450), uB: h(150)]) == [], "aviso nuevo con S abierta al terminar sale")
revisar(!hayAvisoNuevo(antes: lista1, despues: lista1) && sinVerTras([], antes: lista1, despues: lista1, focos: focos).isEmpty, "cambio de sin ver no es aviso nuevo")

// No leídas: snappy
func vint(_ x: Int) -> [UInt8] {
    var x = x, r = [UInt8]()
    while x >= 0x80 { r.append(UInt8(x & 0x7f | 0x80)); x >>= 7 }
    return r + [UInt8(x)]
}
func le(_ x: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((x >> (8 * UInt64($0))) & 0xff) } }
let abcd = Array("abcd".utf8)
revisar(descomprimirSnappy([5, 0x10] + Array("hello".utf8)) == Array("hello".utf8), "snappy: literal corto")
let setenta = [UInt8](repeating: 0x61, count: 35) + [UInt8](repeating: 0x62, count: 35)
revisar(descomprimirSnappy(vint(70) + [60 << 2, 69] + setenta) == setenta, "snappy: literal largo (70)")
revisar(descomprimirSnappy([8, 0x0c] + abcd + [0x01, 4]) == abcd + abcd, "snappy: copia con offset de 1 byte")
revisar(descomprimirSnappy([8, 0x0c] + abcd + [0x0e, 4, 0]) == abcd + abcd, "snappy: copia con offset de 2 bytes")
revisar(descomprimirSnappy([8, 0x0c] + abcd + [0x0f, 4, 0, 0, 0]) == abcd + abcd, "snappy: copia con offset de 4 bytes")
revisar(descomprimirSnappy([8, 0x04, 0x61, 0x62, 0x09, 2]) == Array("abababab".utf8), "snappy: copia solapada")
revisar(descomprimirSnappy([8, 0x04, 0x61, 0x62, 0x09, 5]) == nil && descomprimirSnappy([8, 0x04, 0x61, 0x62, 0x09, 0]) == nil, "snappy: offset fuera de rango o cero -> nil")
revisar(descomprimirSnappy([5, 0x10, 0x61, 0x62]) == nil && descomprimirSnappy([8, 0x0c] + abcd + [0x0f, 4]) == nil, "snappy: truncado -> nil")
revisar(descomprimirSnappy([3, 0x10] + Array("hello".utf8)) == nil && descomprimirSnappy([9, 0x10] + Array("hello".utf8)) == nil, "snappy: largo declarado distinto -> nil")
revisar(descomprimirSnappy(vint(17 << 20) + [0]) == nil && descomprimirSnappy([]) == nil && descomprimirSnappy([0x80]) == nil, "snappy: más de 16 MB o varint roto -> nil")

// No leídas: .log y .ldb armados a mano
let llaveNL = Array("_https://claude.ai".utf8) + [0, 1] + Array("epitaxy-unread-v1".utf8)
let otraLlave = Array("_https://claude.ai".utf8) + [0, 1] + Array("otra-cosa".utf8)
func valorNL(_ ids: [Any], explicitos: [Any] = []) -> [UInt8] {
    let json = try! JSONSerialization.data(withJSONObject: ["state": ["unreadIds": ids, "explicitUnreadIds": explicitos, "stoppedRuns": []], "version": 0])
    return [1] + [UInt8](json)
}
func loteNL(_ seq: UInt64, _ regs: [(UInt8, [UInt8], [UInt8])]) -> [UInt8] {
    regs.reduce(le(seq, 8) + le(UInt64(regs.count), 4)) { r, x in r + [x.0] + vint(x.1.count) + x.1 + (x.0 == 1 ? vint(x.2.count) + x.2 : []) }
}
func logNL(_ lotes: [[UInt8]]) -> [UInt8] { lotes.reduce([]) { $0 + [0, 0, 0, 0] + le(UInt64($1.count), 2) + [1] + $1 } }
func bloqueNL(_ e: [([UInt8], [UInt8])]) -> [UInt8] { e.reduce([]) { $0 + [0] + vint($1.0.count) + vint($1.1.count) + $1.0 + $1.1 } + le(0, 4) + le(1, 4) }
func ldbNL(_ e: [([UInt8], UInt64, UInt8, [UInt8])], comprimir: Bool = false) -> [UInt8] {
    let datos = bloqueNL(e.map { ($0.0 + le($0.1 << 8 | UInt64($0.2), 8), $0.3) })
    let guardado = comprimir ? vint(datos.count) + [61 << 2] + le(UInt64(datos.count - 1), 2) + datos : datos
    let indice = bloqueNL([(Array("z".utf8), vint(0) + vint(guardado.count))])
    let cuerpo = guardado + [comprimir ? 1 : 0, 0, 0, 0, 0] + indice + [0, 0, 0, 0, 0]
    let manijas = vint(0) + vint(0) + vint(guardado.count + 5) + vint(indice.count)
    return cuerpo + manijas + [UInt8](repeating: 0, count: 40 - manijas.count) + le(0xdb4775248b80fb57, 8)
}
var nDir = 0
func dirNL(_ archivos: [String: [UInt8]]) -> URL {
    nDir += 1
    let d = base.appendingPathComponent("leveldb\(nDir)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    for (nombre, b) in archivos { try! Data(b).write(to: d.appendingPathComponent(nombre)) }
    try! Data().write(to: d.appendingPathComponent("LOCK"))
    return d
}
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, llaveNL, valorNL(["local_a", "local_b"], explicitos: ["local_c"]))])])])) == ["local_a", "local_b", "local_c"], "log: unreadIds más explicitUnreadIds")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(llaveNL, 7, 1, valorNL(["local_a"]))])])) == ["local_a"], "ldb sin comprimir")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(otraLlave, 9, 1, valorNL(["local_z"])), (llaveNL, 7, 1, valorNL(["local_a"]))], comprimir: true)])) == ["local_a"], "ldb comprimido con snappy, solo esa llave")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(llaveNL, 10, 1, valorNL(["local_viejo"]))]), "000006.log": logNL([loteNL(20, [(1, llaveNL, valorNL(["local_nuevo"]))])])])) == ["local_nuevo"], "gana la secuencia mayor (log)")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(llaveNL, 30, 1, valorNL(["local_nuevo"]))]), "000006.log": logNL([loteNL(20, [(1, llaveNL, valorNL(["local_viejo"]))])])])) == ["local_nuevo"], "gana la secuencia mayor (ldb)")
revisar(leerNoLeidas(directorio: dirNL(["000006.log": logNL([loteNL(20, [(1, otraLlave, [1]), (1, llaveNL, valorNL(["local_viejo"]))]), loteNL(30, [(1, llaveNL, valorNL(["local_nuevo"]))])])])) == ["local_nuevo"], "dentro del log, el lote más nuevo")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(llaveNL, 10, 1, valorNL(["local_a"]))]), "000006.log": logNL([loteNL(20, [(0, llaveNL, [])])])])) == [], "borrado más nuevo -> vacío")
revisar(leerNoLeidas(directorio: dirNL(["000005.ldb": ldbNL([(llaveNL, 30, 1, valorNL(["local_a"]))]), "000006.log": logNL([loteNL(20, [(0, llaveNL, [])])])])) == ["local_a"], "borrado más viejo no cuenta")
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, llaveNL, valorNL(["local_ok", "local_x;open -a Calculator", "otro", 5, "local_" + String(repeating: "a", count: 65)]))])])])) == ["local_ok"], "ids inválidos se descartan")
let utf16 = [UInt8(0)] + [UInt8](String(data: Data(valorNL(["local_u"]).dropFirst()), encoding: .isoLatin1)!.data(using: .utf16LittleEndian)!)
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, llaveNL, utf16)])])])) == ["local_u"], "valor en UTF-16LE")
let basura: [UInt8] = (0..<5000).map { UInt8(($0 * 7919 + 13) % 256) }
revisar(leerNoLeidas(directorio: dirNL(["000003.log": basura, "000004.ldb": basura])) == nil, "basura -> nil")
revisar(leerNoLeidas(directorio: base.appendingPathComponent("no-existe")) == nil, "directorio inexistente -> nil")
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, otraLlave, [1])])])])) == nil, "llave ausente -> nil")
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, llaveNL, [1] + Array("{no es json".utf8))])])])) == nil, "JSON inválido -> nil")
revisar(leerNoLeidas(directorio: dirNL(["000003.log": logNL([loteNL(5, [(1, llaveNL, [1] + Array("{\"state\":{}}".utf8))])])])) == nil, "formato distinto -> nil")
let truncado = logNL([loteNL(5, [(1, llaveNL, valorNL(["local_a"]))])]) + Array(logNL([loteNL(9, [(1, llaveNL, valorNL(["local_b"]))])]).prefix(30))
revisar(leerNoLeidas(directorio: dirNL(["000003.log": truncado])) == ["local_a"], "log con cola truncada se lee hasta lo completo")
revisar(leerNoLeidas(directorio: dirNL(["000003.ldb": Array(ldbNL([(llaveNL, 50, 1, valorNL(["local_b"]))]).dropLast(3)), "000004.log": logNL([loteNL(5, [(1, llaveNL, valorNL(["local_a"]))])])])) == ["local_a"], "ldb truncado se ignora, el resto se lee")
let grande = logNL([loteNL(99, [(1, llaveNL, valorNL(["local_grande"]))])]) + [UInt8](repeating: 0, count: 17 << 20)
revisar(leerNoLeidas(directorio: dirNL(["000003.log": grande, "000002.log": logNL([loteNL(5, [(1, llaveNL, valorNL(["local_a"]))])])])) == ["local_a"], "archivo de más de 16 MB se ignora")
let dirFirma = dirNL(["000003.log": logNL([])])
let firma1 = firmaNoLeidas(directorio: dirFirma)
try! Data([1, 2, 3]).write(to: dirFirma.appendingPathComponent("000003.log"))
revisar(firma1 != nil && firma1 != firmaNoLeidas(directorio: dirFirma) && firmaNoLeidas(directorio: base.appendingPathComponent("no-existe")) == nil, "firma cambia con el tamaño; sin directorio, nil")

// No leídas: sesiones con sessionId y aviso armado desde el archivo
let dirN = base.appendingPathComponent("noleidas/cuenta/org")
try! FileManager.default.createDirectory(at: dirN, withIntermediateDirectories: true)
func sesionN(_ nombre: String, _ json: [String: Any]) {
    try! JSONSerialization.data(withJSONObject: json).write(to: dirN.appendingPathComponent(nombre))
}
sesionN("local_n1.json", ["sessionId": "local_n1", "cliSessionId": uA, "cwd": "/x/proyecto-a", "lastTurnEdgeAt": 1794327307000, "lastActivityAt": 1794327999000, "title": "Título A"])
sesionN("local_n2.json", ["sessionId": "local_n2", "cliSessionId": uB, "cwd": "/x/proyecto-b", "lastActivityAt": 1794327400000])
sesionN("local_n3.json", ["sessionId": "local_n3", "cliSessionId": uC, "cwd": "/x/c", "lastActivityAt": 1, "isArchived": true])
sesionN("local_n4.json", ["sessionId": "local_x;rm", "cliSessionId": uD, "cwd": "/x/d", "lastActivityAt": 1])
let sesN = leerSesiones(directorio: base.appendingPathComponent("noleidas"))
let n1 = sesN.porId["local_n1"], n2 = sesN.porId["local_n2"]
revisar(sesN.ids[uA] == "local_n1" && sesN.ids[uB] == "local_n2" && sesN.ids[uD] == nil && sesN.ids[uC] == nil, "sessionId por id del CLI, validado, sin archivadas")
revisar(n1?.proyecto == "proyecto-a" && n1?.sesion == uA && n1?.hora == h(1794327307) && n1?.tipo == .termino && n1?.titulo == "Título A", "aviso desde el archivo: cwd, cli, lastTurnEdgeAt y título")
revisar(n2?.hora == h(1794327400) && n2?.titulo == nil && sesN.porId["local_n3"] == nil && sesN.porId.count == 2, "sin lastTurnEdgeAt usa lastActivityAt; archivada e id inválido fuera")

// No leídas: lógica de la lista y sin ver
let uE = "55555555-5555-4555-8555-555555555555"
var sesL = Sesiones()
sesL.ids = [uA: "local_a", uB: "local_b", uC: "local_c", uD: "local_d"]
sesL.porId = ["local_a": Aviso(proyecto: "a", sesion: uA, hora: h(10)), "local_c": Aviso(proyecto: "c", sesion: uC, hora: h(300)), "local_d": Aviso(proyecto: "d", sesion: uD, hora: h(500)), "local_e": Aviso(proyecto: "e", sesion: uE, hora: h(50))]
let baseL = [Aviso(proyecto: "A", sesion: uA, hora: h(1000)), Aviso(proyecto: "B", sesion: uB, hora: h(900))]
let conExtra = conNoLeidas(baseL, noLeidas: ["local_a", "local_c", "local_d", "local_e", "local_sin_archivo"], sesiones: sesL)
revisar(conExtra.map(\.sesion) == [uA, uB, uD, uC, uE], "no leídas fuera de la lista van al final, de más nueva a más vieja")
revisar(conNoLeidas(baseL, noLeidas: ["local_d"], sesiones: sesL).map(\.sesion) == [uA, uB, uD], "la que deja de estar no leída sale")
revisar(conNoLeidas(baseL, noLeidas: nil, sesiones: sesL) == baseL && conNoLeidas(baseL, noLeidas: [], sesiones: sesL) == baseL, "sin conjunto o vacío, la lista queda igual")
revisar(calcularSinVer([uB], noLeidas: ["local_a", "local_d"], antes: baseL, despues: conExtra, sesiones: sesL) == [uA, uD], "sin ver sigue al conjunto")
revisar(calcularSinVer([uA], noLeidas: [], antes: conExtra, despues: conExtra, sesiones: sesL) == [], "conjunto vacío -> nada sin ver")
sesL.focos = focos
revisar(calcularSinVer([], noLeidas: nil, antes: [], despues: lista1, sesiones: sesL) == sinVerTras([], antes: [], despues: lista1, focos: focos) && calcularSinVer([], noLeidas: nil, antes: [], despues: lista1, sesiones: sesL) == [uA, uC], "con nil se usa la heurística")
revisar(!hayAvisoNuevo(antes: baseL, despues: conExtra) && !hayAvisoNuevo(antes: conExtra, despues: baseL), "filas extra no son aviso nuevo")

// Trabajando: marcas en disco, vigencia de 15 minutos, prioridad y sesiones fuera de la lista
let dirTr = base.appendingPathComponent("trabajando")
try! FileManager.default.createDirectory(at: dirTr, withIntermediateDirectories: true)
for nombre in [uA, uB, "no-es-uuid"] { FileManager.default.createFile(atPath: dirTr.appendingPathComponent(nombre).path, contents: nil) }
try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -16 * 60)], ofItemAtPath: dirTr.appendingPathComponent(uB).path)
let marcasTr = leerMarcasTrabajando(directorio: dirTr)
revisar(Set(marcasTr.keys) == [uA, uB], "trabajando: solo marcas con nombre UUID")
revisar(sesionesTrabajando(marcasTr, ahora: Date()) == [uA], "trabajando: marca fresca cuenta, la de más de 15 min no")
revisar(leerMarcasTrabajando(directorio: base.appendingPathComponent("no-existe")).isEmpty, "trabajando: sin carpeta no hay marcas")
revisar(sesionesTrabajando([uA: h(1000)], ahora: h(1000 + 14 * 60 + 59)) == [uA] && sesionesTrabajando([uA: h(1000)], ahora: h(1000 + 15 * 60)) == [], "trabajando: el corte es a los 15 minutos justos")
let avE = Aviso(proyecto: "e", sesion: uA, hora: h(1), tipo: .espera), avT = Aviso(proyecto: "t", sesion: uB, hora: h(1))
revisar(estadoFila(avE, trabajando: [uA], sinVer: [uA]) == .esperando, "prioridad: esperando gana a trabajando y sin ver")
revisar(estadoFila(avT, trabajando: [uB], sinVer: [uB]) == .trabajando, "prioridad: trabajando gana a sin ver")
revisar(estadoFila(avT, trabajando: [], sinVer: [uB]) == .sinVer && estadoFila(avT, trabajando: [uA], sinVer: []) == .normal, "prioridad: sin ver y normal")
var sesTr = Sesiones()
sesTr.ids = [uA: "local_a", uB: "local_b", uC: "local_c", uD: "local_d", uE: "local_a"]
sesTr.porId = ["local_a": Aviso(proyecto: "a", sesion: uA, hora: h(10)), "local_c": Aviso(proyecto: "c", sesion: uC, hora: h(300), titulo: "Tc", carpeta: "cc"), "local_d": Aviso(proyecto: "d", sesion: uD, hora: h(500))]
let listaTr = [Aviso(proyecto: "A", sesion: uA, hora: h(1000))]
let extrasTr = extrasTrabajando(listaTr, trabajando: [uA, uB, uC, uD, uE], sesiones: sesTr)
revisar(extrasTr.map(\.sesion) == [uD, uC], "trabajando fuera de la lista va al final, de más nueva a más vieja; sin archivo o ya en la lista no")
revisar(extrasTr.last?.titulo == "Tc" && extrasTr.last?.carpeta == "cc" && extrasTr.last?.tipo == .termino, "trabajando fuera de la lista lleva título y carpeta")
revisar(extrasTrabajando(listaTr, trabajando: [], sesiones: sesTr).isEmpty && extrasTrabajando(listaTr, trabajando: [uA], sesiones: sesTr).isEmpty, "sin trabajando fuera de la lista, no hay filas extra")

// Orden de pantalla: activas sin tope, normales completan hasta 6 y salen pasadas las 12 horas
let ahoraP = h(100_000)
func uP(_ i: Int) -> String { String(format: "99999999-0000-4000-8000-%012d", i) }
func avP(_ i: Int, _ hora: Date, tipo: Tipo = .termino) -> Aviso { Aviso(proyecto: "p\(i)", sesion: uP(i), hora: hora, tipo: tipo) }
let ochoActivas = (1...8).map { avP($0, h(99_000 - Double($0)), tipo: $0 <= 3 ? .espera : .termino) }
let normalesP = (11...20).map { avP($0, h(99_500 - Double($0))) }
let trabP: Set<String> = [uP(4), uP(5)], sinVerP: Set<String> = [uP(6), uP(7), uP(8)]
let pant8 = ordenPantalla(ochoActivas + normalesP, trabajando: trabP, sinVer: sinVerP, ahora: ahoraP)
revisar(pant8.map(\.sesion) == (1...8).map(uP), "pantalla: 8 activas se muestran las 8 y ninguna normal")
let pant2 = ordenPantalla(normalesP + [avP(1, h(90_000), tipo: .espera), avP(2, h(80_000))], trabajando: [], sinVer: [uP(2)], ahora: ahoraP)
revisar(pant2.map(\.sesion) == [uP(1), uP(2), uP(11), uP(12), uP(13), uP(14)], "pantalla: 2 activas + 10 normales muestran 2 + 4, activas antes que normales")
let vieja = avP(30, h(100_000 - 12 * 3600 - 1)), justa = avP(31, h(100_000 - 12 * 3600)), activaVieja = avP(32, h(1), tipo: .espera)
revisar(ordenPantalla([vieja], trabajando: [], sinVer: [], ahora: ahoraP).isEmpty, "pantalla: normal de más de 12 h no aparece")
revisar(ordenPantalla([activaVieja, vieja], trabajando: [], sinVer: [], ahora: ahoraP) == [activaVieja], "pantalla: activa de más de 12 h sí aparece")
revisar(ordenPantalla([justa, vieja], trabajando: [], sinVer: [], ahora: ahoraP) == [justa], "pantalla: corte justo en 12 h (12 h exactas se ve, un segundo más no)")
revisar(ordenPantalla([vieja], trabajando: [uP(30)], sinVer: [], ahora: ahoraP) == [vieja] && ordenPantalla([vieja], trabajando: [], sinVer: [uP(30)], ahora: ahoraP) == [vieja], "pantalla: trabajando o sin ver vieja vuelve a aparecer")
let mezcla = [avP(1, h(99_000)), avP(2, h(99_100)), avP(3, h(98_000), tipo: .espera), avP(4, h(99_200))]
revisar(ordenPantalla(mezcla, trabajando: [uP(1)], sinVer: [], ahora: ahoraP).map(\.sesion) == [uP(1), uP(3), uP(4), uP(2)], "pantalla: activas por hora sin ordenar por tipo, normales después por hora")
revisar(ordenPantalla([], trabajando: [uA], sinVer: [uB], ahora: ahoraP).isEmpty, "pantalla: lista vacía")
// Una normal que empieza a trabajar sube en pantalla, pero la lista base (la que decide el aviso nuevo) no cambia.
let antesP = ordenPantalla(mezcla, trabajando: [], sinVer: [], ahora: ahoraP), despuesP = ordenPantalla(mezcla, trabajando: [uP(1)], sinVer: [], ahora: ahoraP)
revisar(antesP.first != despuesP.first && !hayAvisoNuevo(antes: mezcla, despues: mezcla), "pantalla: reordenar no cuenta como aviso nuevo")

// Fila actual: la sesión con el foco más reciente, solo si está en las filas
let filasA = [avP(1, h(99_000)), avP(2, h(98_000)), avP(3, h(97_000))]
let idsA = [uP(1): "local_1", uP(2): "local_2", uP(3): "local_3", uP(4): "local_2", uP(9): "local_9"]
revisar(filaActual(filasA, focos: [uP(1): h(10), uP(2): h(30), uP(3): h(20)], ids: idsA) == uP(2), "actual: la de foco más reciente, en la lista")
revisar(filaActual(filasA, focos: [uP(1): h(10), uP(2): h(30), uP(9): h(40)], ids: idsA) == nil, "actual: la de foco más reciente no está en la lista, nada")
revisar(filaActual([avP(4, h(99_000)), avP(1, h(98_000))], focos: [uP(1): h(10), uP(2): h(30), uP(4): h(30)], ids: idsA) == uP(4), "actual: sesión con dos ids del CLI cuenta una vez y resalta la fila que está")
revisar(filaActual(filasA, focos: [:], ids: idsA) == nil, "actual: sin focos, nada")
revisar(filaActual(filasA, focos: [uP(1): h(30), uP(3): h(30), uP(2): h(10)], ids: idsA) == nil, "actual: empate entre dos sesiones, nada")
revisar(filaActual(filasA, focos: [uP(9): h(5)], ids: idsA) == nil && filaActual(filasA, focos: [uP(1): h(5)], ids: idsA) == uP(1), "actual: filas sin foco no ganan; la única con foco sí")

// Receptor: funciones puras
let claveFalsa = "clave-falsa-de-prueba-1234"
func pedido(_ linea: String = "POST /abrir HTTP/1.1", clave: String? = claveFalsa, cuerpo: String = "sesion=\(uA)") -> Data {
    var texto = "\(linea)\r\nHost: x\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: \(cuerpo.utf8.count)\r\nConnection: close\r\n"
    if let clave { texto += "X-Clave: \(clave)\r\n" }
    return Data((texto + "\r\n" + cuerpo).utf8)
}
revisar(analizarPedido(pedido(), clave: claveFalsa) == .sesion(uA), "petición válida -> sesión")
revisar(analizarPedido(pedido("GET /abrir HTTP/1.1"), clave: claveFalsa) == .error(400), "GET -> 400")
revisar(analizarPedido(pedido("POST /estado HTTP/1.1"), clave: claveFalsa) == .error(400), "ruta distinta -> 400")
revisar(analizarPedido(pedido(clave: nil), clave: claveFalsa) == .error(401), "sin X-Clave -> 401")
revisar(analizarPedido(pedido(clave: "clave-falsa-de-prueba-1235"), clave: claveFalsa) == .error(401), "clave mala -> 401")
revisar(analizarPedido(pedido(cuerpo: "sesion=no-es-uuid"), clave: claveFalsa) == .error(400), "sesion que no es UUID -> 400")
revisar(analizarPedido(pedido(cuerpo: "sesion=\(uA)\n"), clave: claveFalsa) == .error(400), "UUID con salto de línea -> 400")
revisar(analizarPedido(pedido(cuerpo: "sesion=\(uA)&x=1"), clave: claveFalsa) == .error(400), "cuerpo con más campos -> 400")
revisar(analizarPedido(pedido(cuerpo: String(repeating: "a", count: 2100)), clave: claveFalsa) == .error(400), "más de 2048 bytes -> 400")
revisar(analizarPedido(pedido().dropLast(5), clave: claveFalsa) == nil, "cuerpo incompleto -> espera más bytes")
revisar(igualesTiempoConstante("abcdef", "abcdef") && !igualesTiempoConstante("abcdef", "abcdeg") && !igualesTiempoConstante("abc", "abcdef") && !igualesTiempoConstante("abcdef", ""), "comparación en tiempo constante")
var limitador = Limitador()
let primeras = (0..<20).allSatisfy { limitador.permitir(ahora: 1000 + Double($0)) }
revisar(primeras && !limitador.permitir(ahora: 1030), "limitador: la 21 dentro del minuto se rechaza")
revisar(limitador.permitir(ahora: 1061), "limitador: vuelve a aceptar al pasar el minuto")

// Receptor: sin clave o con clave corta no arranca
let rutaClaveFalsa = base.appendingPathComponent("clave")
revisar(Receptor(avisos: { [] }, abrir: { _ in }, puerto: 50999, rutaClave: rutaClaveFalsa) == nil, "sin archivo de clave no arranca")
try! "corta\n".write(to: rutaClaveFalsa, atomically: true, encoding: .utf8)
revisar(Receptor(avisos: { [] }, abrir: { _ in }, puerto: 50999, rutaClave: rutaClaveFalsa) == nil, "clave de menos de 16 no arranca")

// Receptor: red real en un puerto alto, clave falsa y acción de abrir falsa
try! " \(claveFalsa)\n".write(to: rutaClaveFalsa, atomically: true, encoding: .utf8)
let puerto = puertoLibre()
var abiertas: [String] = []
let receptor = Receptor(avisos: { [Aviso(proyecto: "A", sesion: uA, hora: Date())] }, abrir: { abiertas.append($0.sesion) }, puerto: puerto, rutaClave: rutaClaveFalsa)
revisar(receptor != nil, "receptor arranca con clave falsa en el puerto \(puerto)")
func curl(_ argumentos: [String]) -> String {
    let proceso = Process(), salida = Pipe()
    proceso.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    proceso.arguments = ["-4", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8", "-H", "Connection: close"] + argumentos + ["http://127.0.0.1:\(puerto)/abrir"]
    proceso.standardOutput = salida
    try! proceso.run()
    proceso.waitUntilExit()
    return String(data: salida.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
func corridaReceptor() {
    DispatchQueue.global().async {
        let clave = ["-H", "X-Clave: \(claveFalsa)"]
        var codigos = [
            curl(clave + ["--data", "sesion=\(uA)"]),
            curl(clave + ["--data", "sesion=\(uB)"]),
            curl(["-H", "X-Clave: otra-clave-que-no-es-1234", "--data", "sesion=\(uA)"]),
            curl(clave),
        ]
        let abiertasAntes = DispatchQueue.main.sync { abiertas }
        for _ in 0..<16 { codigos.append(curl(clave + ["--data", "sesion=\(uB)"])) }
        codigos.append(curl(clave + ["--data", "sesion=\(uA)"]))
        DispatchQueue.main.async {
            print("      códigos: \(codigos.joined(separator: " "))")
            revisar(Array(codigos.prefix(4)) == ["200", "404", "401", "400"], "red: 200, 404, 401, 400 (GET)")
            revisar(codigos[4..<20].allSatisfy { $0 == "404" } && codigos[20] == "429", "red: la petición 21 recibe 429")
            revisar(abiertasAntes == [uA] && abiertas == [uA], "red: abrir se llamó una sola vez, con la sesión esperada")
            print(fallas == 0 ? "TODO OK" : "\(fallas) FALLAS")
            exit(fallas == 0 ? 0 : 1)
        }
    }
}


// Emisor: cuerpo
let av1 = Aviso(proyecto: "P1", sesion: uA, hora: h(1794328000), tipo: .espera, titulo: "Dijo \"hola\" con tildes áé y emoji 🎉")
let av2 = Aviso(proyecto: "P2", sesion: uB, hora: h(1794328100))
func objetoEstado(_ d: Data) -> [String: Any]? { try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
let c1 = objetoEstado(cuerpoEstado(avisos: [av1, av2], sinVer: [uB], nuevo: true))
let l1 = c1?["avisos"] as? [[String: Any]]
revisar(c1?["nuevo"] as? Bool == true && l1?.count == 2, "cuerpo: JSON válido con nuevo y dos avisos")
revisar(l1?[0]["nombre"] as? String == "Dijo \"hola\" con tildes áé y emoji 🎉" && l1?[1]["nombre"] as? String == "P2", "cuerpo: orden y nombres con comillas, tildes y emoji")
revisar(l1?[0]["sesion"] as? String == uA && l1?[0]["hora"] as? Int == 1794328000, "cuerpo: sesion y hora como número")
revisar(l1?[0]["esperando"] as? Bool == true && l1?[1]["esperando"] as? Bool == false, "cuerpo: esperando")
revisar(l1?[0]["sinVer"] as? Bool == false && l1?[1]["sinVer"] as? Bool == true, "cuerpo: sinVer")
let muchos = (0..<15).map { Aviso(proyecto: "P\($0)", sesion: String(format: "00000000-0000-4000-8000-%012d", $0), hora: h(Double($0))) }
let cm = objetoEstado(cuerpoEstado(avisos: muchos, sinVer: [], nuevo: false))
let lm = cm?["avisos"] as? [[String: Any]]
revisar(lm?.count == 12 && lm?.first?["nombre"] as? String == "P0" && lm?.last?["nombre"] as? String == "P11" && cm?["nuevo"] as? Bool == false, "cuerpo: tope de 12 y nuevo false")
let cc = objetoEstado(cuerpoEstado(avisos: [Aviso(proyecto: "P", sesion: uA, hora: h(1), titulo: "T", carpeta: "instagram"), Aviso(proyecto: "P", sesion: uB, hora: h(2), carpeta: "x"), Aviso(proyecto: "P", sesion: uC, hora: h(3), titulo: "T", carpeta: "T")], sinVer: [], nuevo: false))
let lc = cc?["avisos"] as? [[String: Any]]
revisar(lc?[0]["carpeta"] as? String == "instagram" && lc?[1]["carpeta"] == nil && lc?[2]["carpeta"] == nil, "cuerpo: carpeta solo cuando es visible")
revisar(l1?[0]["carpeta"] == nil, "cuerpo: sin carpeta no hay clave")
let peor = cuerpoEstado(avisos: muchos.map { Aviso(proyecto: String(repeating: "ñ", count: 40), sesion: $0.sesion, hora: $0.hora, titulo: String(repeating: "🎉", count: 60), carpeta: String(repeating: "🎉", count: 40)) }, sinVer: [], nuevo: true)
print("peor caso:", peor.count, "bytes")
revisar(peor.count <= 8192, "cuerpo: peor caso cabe en 8192 bytes")

// Emisor: sin clave o con clave corta no arranca
let rutaClaveE = base.appendingPathComponent("claveE")
revisar(Emisor(host: "127.0.0.1", puerto: 50998, rutaClave: rutaClaveE) == nil, "emisor: sin archivo de clave no arranca")
try! "corta\n".write(to: rutaClaveE, atomically: true, encoding: .utf8)
revisar(Emisor(host: "127.0.0.1", puerto: 50998, rutaClave: rutaClaveE) == nil, "emisor: clave de menos de 16 no arranca")

// Emisor: el host sale del archivo de configuración del iPad
let rutaIpadE = base.appendingPathComponent("ipad")
try! "\(claveFalsa)\n".write(to: rutaClaveE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) == nil, "emisor: sin archivo del iPad no arranca")
try! " \n".write(to: rutaIpadE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) == nil, "emisor: archivo del iPad vacío no arranca")
try! "ipad;rm -rf\n".write(to: rutaIpadE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) == nil, "emisor: host inválido no arranca")
try! "mi ipad.local\n".write(to: rutaIpadE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) == nil, "emisor: host con espacio no arranca")
try! "mi-ipad.local\n".write(to: rutaIpadE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) != nil, "emisor: host válido con clave arranca")
try! "corta\n".write(to: rutaClaveE, atomically: true, encoding: .utf8)
revisar(Emisor(rutaIpad: rutaIpadE, rutaClave: rutaClaveE) == nil, "emisor: host válido con clave corta no arranca")

// Emisor: red real contra un servidor local falso (nunca el iPad)
try! "\(claveFalsa)\n".write(to: rutaClaveE, atomically: true, encoding: .utf8)
let puertoE = puertoLibre()
var modoE = "401"
var recibidos: [String] = []
let servidorE = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: puertoE)!)
func leerPeticionE(_ c: NWConnection, _ previo: Data) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { datos, _, _, error in
        let todo = previo + (datos ?? Data())
        let texto = String(decoding: todo, as: UTF8.self)
        guard let fin = texto.range(of: "\r\n\r\n") else { return error == nil ? leerPeticionE(c, todo) : c.cancel() }
        let largo = texto.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
        guard todo.count - texto[..<fin.upperBound].utf8.count >= largo else { return error == nil ? leerPeticionE(c, todo) : c.cancel() }
        recibidos.append(texto)
        guard modoE != "mudo" else { return }
        c.send(content: Data("HTTP/1.1 \(modoE) x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }
}
servidorE.newConnectionHandler = { c in c.start(queue: .main); leerPeticionE(c, Data()) }
servidorE.start(queue: .main)
var tE: TimeInterval = 1000
let emisor = Emisor(host: "127.0.0.1", puerto: puertoE, rutaClave: rutaClaveE, reloj: { tE })!
var resultadosE: [Bool] = []
func cuerpoDe(_ i: Int) -> [String: Any]? {
    guard i < recibidos.count, let r = recibidos[i].range(of: "\r\n\r\n") else { return nil }
    return objetoEstado(Data(recibidos[i][r.upperBound...].utf8))
}
var pasosE: [() -> Void] = [
    { emisor.marcarNuevo(); emisor.cambio([av1, av2], [uB]) },                 // 0: 401 -> fallo
    { tE += 5.5; emisor.tick() },                                              // 1: reintento, mismo modo 401
    { modoE = "200"; tE += 5.5; emisor.tick() },                               // 2: reintento que llega
    { emisor.cambio([av2], []) },                                              // 3: cambio sin nuevo
    { modoE = "mudo"; emisor.cambio([av1], []) },                              // 4: sin respuesta -> fallo a los 4 s
    { modoE = "200"; tE += 5.5; emisor.tick() },                               // 5: reintento llega
    { tE += 61; emisor.tick() },                                               // 6: latido
]
func siguienteE() {
    if !pasosE.isEmpty { return pasosE.removeFirst()() }
    let p = recibidos.first ?? ""
    revisar(resultadosE == [false, false, true, true, false, true, true], "emisor: 401 y servidor mudo fallan, 200 entrega (\(resultadosE))")
    revisar(p.hasPrefix("POST /estado HTTP/1.1\r\n") && p.contains("\r\nX-Clave: \(claveFalsa)\r\n") && p.contains("\r\nContent-Type: application/json\r\n") && p.contains("\r\nConnection: close\r\n") && p.contains("\r\nHost: 127.0.0.1:\(puertoE)\r\n"), "emisor: POST /estado bien formado con la clave")
    revisar(recibidos.count == 7, "emisor: siete envíos en total (\(recibidos.count))")
    let nuevos = (0..<recibidos.count).map { cuerpoDe($0)?["nuevo"] as? Bool }
    revisar(nuevos == [true, true, true, false, false, false, false], "emisor: nuevo se mantiene en los reintentos hasta que llega (\(nuevos))")
    revisar((cuerpoDe(2)?["avisos"] as? [[String: Any]])?.count == 2 && (cuerpoDe(3)?["avisos"] as? [[String: Any]])?.count == 1, "emisor: cada envío lleva el estado más reciente")
    servidorE.cancel()
    corridaReceptor()
}
emisor.alResponder = { ok in resultadosE.append(ok); siguienteE() }

siguienteE()
dispatchMain()
