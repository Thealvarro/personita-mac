// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
// Personaje propio de la barra: paleta y cuadro quieto de 30 x 52 (24 x 48 de dibujo, 4 filas vacías arriba para el globo y las zetas,
// 1 columna vacía a la izquierda y 5 a la derecha para el balanceo y el brazo del saludo); las demás poses se arman abajo.
import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }
}

enum Sprites {
    static let paleta: [Character: Color] = [
        "K": Color(rgb: 0x1a1414),
        "D": Color(rgb: 0x2b2422),
        "k": Color(rgb: 0x1e2232),
        "N": Color(rgb: 0x2c364e),
        "c": Color(rgb: 0x48536e),
        "W": Color(rgb: 0xfdf8f5),
        "S": Color(rgb: 0xfeca9f),
        "B": Color(rgb: 0xf39f74),
        "q": Color(rgb: 0xd36b4d),
        "n": Color(rgb: 0x0c3672),
        "w": Color(rgb: 0x136fad),
        "b": Color(rgb: 0x2fb4e0),
        "v": Color(rgb: 0x1b88b9),
        "u": Color(rgb: 0x115785),
        "g": Color(rgb: 0xc1bab6),
        "z": Color(rgb: 0xa49e9d),
        "a": Color(rgb: 0xb9c6dc),
    ]
    static let quieta: [String] = [
        "..............................",
        "..............................",
        "..............................",
        "..............................",
        "........KKKKKKKKK.............",
        "......KKkNNNNNNNkK............",
        "....KKNkNNNNWNNNWWK...........",
        "...KkNkNNNNWNWNWNNkK..........",
        "..KNNNkNNNNWWWNWNNNK..........",
        "..KNNNkNNNNWNWNNWWNK..........",
        "..KNNNkNNNNNNNkkNNkKKKK.......",
        ".KNNNNkNNkkkkccccccccccK......",
        ".KNNNNkNkccccccKKKKKKKKcK.....",
        ".KNNNkkkccccckKBBBBKKKKkK.....",
        ".KNNkKkccccKKKBBSSSBKkkKK.....",
        ".KNkKKKKKKKBBBSSSSSSBKKK......",
        ".KkKKDKBBBKKKKKSSSKKKK........",
        ".KKKKKKBSnnnnnnnSnnnnnn.......",
        "..KKKwwwnnBBBKBnnnBKBnn.......",
        "..KSSKKBSnSSSKSnSnSKSn........",
        ".KSqqSKBSnSSSKSnSnSKSn........",
        ".KSBqSKBSnSSSSSnSnSSSn........",
        ".KSBqBKBSSnnnnnSqqnnn.........",
        "..KSSSBKSSSSKKKKKKKSBK........",
        "...KKKBKDSSSDKSSSKDSBK........",
        ".....KKKDDSDDSKKKSDDKK........",
        "......KKDDDDgSSDSSDDK.........",
        "....KKKKKKDDgggzggDDK.........",
        "....KbbbKKKDDgggggDK..........",
        "..KKbbbbbbbKKKggzKK...........",
        "..KbbuuubbbbbKKKKbbK..........",
        "..KvubbbuubbgbKbbbuK..........",
        "...KbbbbbbuuWwbwWubbK.........",
        "..KbbbbwbbbwWwuuWbbbK.........",
        ".KbbbbbbubbvWbbvWbubK.........",
        ".KbbbbbvKbbvWbbvWbKbbK........",
        ".KbbwwwvKbbbubbbwbKwwK........",
        "..KwuwuKvbbubbbbbwKuwK........",
        "..KuSSSKvvubbbbbbbKSSK........",
        "..KSSSSSKuvvbbbbbvKSSK........",
        "..KBSSSBKKKKKKKKKKKBSK........",
        "...KBBBKkNNNNNNNNNKBK.........",
        "....KKKkNNNNNNKNNNKK..........",
        ".....KkkNNNNKKkNNNK...........",
        ".....KKkNNNNKKkNNNK...........",
        ".....KkNNNkKKKkNNNK...........",
        ".....KkNNNkK.KkkNNK...........",
        ".....KkKKKKK.KkkKKK...........",
        ".....KKcWWWK.KKKcWWK..........",
        "....KcccczzzKKccccczK.........",
        "....KWWWWWWWKKWWWWWWK.........",
        "....KKKKKKKKKKKKKKKKK.........",
    ]
}

// Parche sobre la grilla: filas que se escriben desde (fila, columna); un espacio deja lo que había abajo.
struct Parche: Equatable {
    let fila: Int, columna: Int
    let filas: [String]
}

// Pose de un cuadro de la animación: hacia dónde miran los ojos, hacia dónde se corre el cuerpo (-1, 0 o 1 pixel),
// ojos cerrados o mirando abajo, cuánto se ladea la gorra (la cabeza apoyada) y los parches de los brazos.
struct Pose: Equatable {
    var ojos = 0
    var cuerpo = 0
    var cerrados = false
    var abajo = false
    var cabeza = 0
    var parches: [Parche] = []
}

// Gesto del monito según el panel de arriba: esperando > trabajando > duerme > reposo. Duerme si el último aviso
// tiene más de 30 minutos o no hay avisos (antiguedad: segundos desde el último aviso, nil si no hay).
enum Gesto: Equatable {
    case reposo, saluda, teclea, duerme
    static let dormirTras: TimeInterval = 30 * 60
    init(esperando: Bool, trabajando: Bool, antiguedad: TimeInterval?) {
        self = esperando ? .saluda : trabajando ? .teclea : (antiguedad ?? .infinity) > Gesto.dormirTras ? .duerme : .reposo
    }
}

extension Sprites {
    // Filas de los ojos, columnas de las pupilas y última fila que se balancea (de ahí para abajo, las piernas quedan fijas).
    static let filasOjos = 18...20
    static let pupilas = [13, 19]
    static let ultimaFilaCuerpo = 41
    // Filas de la gorra, que se corren con la cabeza ladeada.
    static let filasGorra = 4...13

    static func cuadro(_ pose: Pose) -> [String] {
        var g = quieta.enumerated().map { y, fila in
            var f = fila
            // Cada ojo se mueve dentro de su lente (interior, sin tocar el marco).
            if filasOjos.contains(y) {
                f = correr(f, pose.ojos, desde: 10, hasta: 15, relleno: "S")
                f = correr(f, pose.ojos, desde: 18, hasta: 21, relleno: "S")
            }
            if filasGorra.contains(y) { f = correr(f, pose.cabeza, desde: 0, hasta: f.count, relleno: ".") }
            return Array(f)
        }
        for c in pupilas.map({ $0 + pose.ojos }) {
            // Mirando abajo, la pupila baja una fila; con los ojos cerrados queda una línea en la fila del medio.
            if pose.abajo { g[18][c] = "B"; g[21][c] = "K" }
            if pose.cerrados {
                g[18][c] = "B"; g[20][c] = "S"
                for x in c - 1...c + 1 { g[19][x] = "K" }
            }
        }
        for p in pose.parches {
            for (i, f) in p.filas.enumerated() {
                for (j, letra) in f.enumerated() where letra != " " { g[p.fila + i][p.columna + j] = letra }
            }
        }
        return g.enumerated().map { y, f in
            y <= ultimaFilaCuerpo ? correr(String(f), pose.cuerpo, desde: 0, hasta: f.count, relleno: ".") : String(f)
        }
    }

    // Corre los caracteres de [desde, hasta) un lugar a la izquierda (-1) o derecha (1); el hueco se llena con relleno.
    private static func correr(_ fila: String, _ d: Int, desde: Int, hasta: Int, relleno: Character) -> String {
        guard d != 0 else { return fila }
        var c = Array(fila)
        let tramo = c[desde..<hasta]
        c.replaceSubrange(desde..<hasta, with: d > 0 ? [relleno] + Array(tramo.dropLast()) : Array(tramo.dropFirst()) + [relleno])
        return String(c)
    }

    // Saludo: borra el brazo caído de la derecha y levanta ese brazo con la mano a la altura de la cabeza.
    static let sinBrazoDerecho = Parche(fila: 31, columna: 18, filas: [
        "K..",
        "K..",
        "K..",
        "K..",
        " ...",
        " ...",
        " ...",
        " ...",
        " ...",
        " ...",
        " ..",
    ])
    static let brazoArriba = Parche(fila: 22, columna: 18, filas: [
        "     KbbvK",
        "     KbbvK",
        "     KbbvK",
        "    KbbbvK",
        "   KbbbvK",
        "  KbbbvK",
        " KbbbvK",
        " bbbvK",
        " bbvK",
        " KKK",
    ])
    // La mano en los dos cuadros del saludo: derecha y corrida un pixel hacia afuera.
    static let manoArriba1 = Parche(fila: 16, columna: 23, filas: [
        " KKKK",
        "KSSSSK",
        "KSSSSK",
        "KSSSSK",
        "KBSSBK",
        "KbbvKK",
    ])
    static let manoArriba2 = Parche(fila: 16, columna: 23, filas: [
        "  KKKK",
        " KSSSSK",
        " KSSSSK",
        " KSSSSK",
        " KBSSBK",
        ".KbbvKK",
    ])
    // Globo con un "!" sobre la cabeza mientras saluda; la colita apunta a la gorra.
    static let globo = Parche(fila: 0, columna: 23, filas: [
        ".KKKKK.",
        "KWWWWWK",
        "KWWKWWK",
        "KWWKWWK",
        "KWWKWWK",
        "KWWWWWK",
        "KWWKWWK",
        "KWWWWWK",
        "KWKKKK.",
        "KK.....",
    ])
    // Tecleo: un teclado delante, a la altura de las manos (tapa las rodillas).
    static let teclado = Parche(fila: 40, columna: 0, filas: [
        "..KKKKKKKKKKKKKKKKKKKK",
        ".KcWWcWWcWWcWWcWWcWWcK",
        ".KWWcWWcWWcWWcWWcWWcWK",
        ".KccccWWWWWWWWWWWccccK",
        ".KNNNNNNNNNNNNNNNNNNNK",
        ".KKKKKKKKKKKKKKKKKKKKK",
    ])
    // Las manos sobre las teclas, un poco hacia el centro: en cada cuadro una sube un pixel y la otra queda apoyada.
    static let manosTecleo1 = Parche(fila: 36, columna: 0, filas: [
        "..KwuwuwKbbbubbbwbKwwK.",
        "...KuSSSKbbubbbbbKuwK..",
        "...KSSSSSKubbbbbbKSSK..",
        "...KBSSSBKvvbbbbbKSSK..",
        "..KKKBBBKKKKKKKKKKBSKK.",
        ".KcWWcWWcWWcWWcWWKBKcK.",
    ])
    static let manosTecleo2 = Parche(fila: 36, columna: 0, filas: [
        ".KbbwwwvKbbbubbbwKuwK..",
        "...KwuwuKbbubbbbbKSSK..",
        "...KuSSSKvubbbbbbKSSK..",
        "...KSSSSSKvvbbbbbKBSK..",
        "..KKBSSSBKKKKKKKKKBKKK.",
        ".KcWKBBBKWWcWWcWWcWWcK.",
    ])
    // Duerme con la mejilla apoyada en una almohada parada junto a la cara (puntas en las esquinas, sombra gris azulada
    // y una hendidura donde se hunde la cara); la mano derecha la sujeta por debajo.
    static let almohada = Parche(fila: 14, columna: 19, filas: [
        " KK      KK",
        " KWKKKKKKWK",
        " KWWWWWWWWK",
        " KWWWWWWWK.",
        " nKaWWWWWK.",
        " nKaWWWWWK.",
        " nKaWWWWWK.",
        " nKaWWWWWK.",
        "  KaWWWWWK.",
        " KWWWWWWWWK",
        " KWWWWWWWaK",
        " KaWKKKKaaK",
        " KK      KK",
    ])
    static let manoAlmohada = Parche(fila: 24, columna: 18, filas: [
        "     KKKK",
        "    KSSSSK",
        "    KBSSBK",
        "   KbbbvK",
        "  KbbbvK",
        " KbbbvK",
        " bbbvK",
        " bbvK",
        " KKK",
    ])
    // Zetas celestes (blancas se leían junto al "AC" de la gorra) que suben: una chica, después una grande encima, y la grande sola.
    static let zChica = Parche(fila: 6, columna: 24, filas: [
        "bbbb",
        "..b.",
        ".b..",
        "bbbb",
    ])
    static let zGrande = Parche(fila: 0, columna: 25, filas: [
        "bbbbb",
        "...b.",
        "..b..",
        ".b...",
        "bbbbb",
    ])

    static let saludo = [Pose(parches: [sinBrazoDerecho, brazoArriba, manoArriba1, globo]), Pose(parches: [sinBrazoDerecho, brazoArriba, manoArriba2, globo])]
    static let tecleo = [Pose(abajo: true, parches: [teclado, manosTecleo1]), Pose(abajo: true, parches: [teclado, manosTecleo2])]
    static let sueno = [Pose(cerrados: true, cabeza: 1, parches: [almohada, sinBrazoDerecho, manoAlmohada, zChica]), Pose(cerrados: true, cabeza: 1, parches: [almohada, sinBrazoDerecho, manoAlmohada, zChica, zGrande]), Pose(cerrados: true, cabeza: 1, parches: [almohada, sinBrazoDerecho, manoAlmohada, zGrande])]

    // Reposo en pasos de 0,25 s: quieta un rato, mira a un lado, se balancea, pestañea, mira al otro...
    static let secuencia: [(Pose, Int)] = [
        (Pose(), 14), (Pose(ojos: -1), 6), (Pose(), 5),
        (Pose(cuerpo: -1), 3), (Pose(), 2), (Pose(cuerpo: 1), 3), (Pose(), 6), (Pose(cerrados: true), 1), (Pose(), 3),
        (Pose(ojos: 1), 7), (Pose(), 4), (Pose(ojos: -1, cuerpo: -1), 4), (Pose(), 8), (Pose(cerrados: true), 1), (Pose(), 3),
        (Pose(cuerpo: 1), 3), (Pose(), 2), (Pose(cuerpo: -1), 3), (Pose(), 2), (Pose(ojos: 1, cuerpo: 1), 5), (Pose(), 9),
    ]
    static let paso = 0.25

    // Saluda cambiando la mano cada 0,5 s, teclea cambiando cada 0,25 s y duerme cambiando las zetas cada 0,8 s; en reposo sigue la secuencia.
    static func pose(en fecha: Date, gesto: Gesto = .reposo) -> Pose {
        let t = fecha.timeIntervalSinceReferenceDate
        switch gesto {
        case .saluda: return saludo[Int(t / 0.5) % 2]
        case .teclea: return tecleo[Int(t / paso) % 2]
        case .duerme: return sueno[Int(t / 0.8) % sueno.count]
        case .reposo:
            let total = secuencia.reduce(0) { $0 + $1.1 }
            var resto = Int(t / paso) % total
            for (pose, pasos) in secuencia {
                if resto < pasos { return pose }
                resto -= pasos
            }
            return Pose()
        }
    }
}

// La personita dibujada a 2 pt por pixel (4 px exactos en pantallas Retina), sin suavizado.
struct Monito: View {
    var pose = Pose()
    @Environment(\.displayScale) private var escala

    var body: some View {
        Canvas { ctx, _ in
            let t: CGFloat = 2
            // Redondea a pixeles del dispositivo para que los bordes queden nítidos.
            let r = { (v: CGFloat) in (v * escala).rounded() / escala }
            for (y, fila) in Sprites.cuadro(pose).enumerated() {
                for (x, letra) in fila.enumerated() {
                    guard let color = Sprites.paleta[letra] else { continue }
                    // Se dibujan todas las columnas: al balancearse, el cuerpo ocupa la primera o la que sigue al dibujo.
                    let x0 = r(CGFloat(x) * t), y0 = r(CGFloat(y) * t)
                    ctx.fill(Path(CGRect(x: x0, y: y0, width: r(CGFloat(x + 1) * t) - x0, height: r(CGFloat(y + 1) * t) - y0)), with: .color(color))
                }
            }
        }
        .frame(width: 60, height: 104)
    }
}
