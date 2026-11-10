// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Álvaro Cofré (SICS) - alvarocofre.dev
// Copiado de ipad-personita/App/Sprites.swift (paleta y cuadro quieto; las demás poses se arman abajo). El original no se toca.
import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }
}

enum Sprites {
    static let paleta: [Character: Color] = [
        "K": Color(rgb: 0x1b1630),
        "H": Color(rgb: 0x4b2a6b),
        "h": Color(rgb: 0x7a4aa8),
        "P": Color(rgb: 0x2f2f3d),
        "p": Color(rgb: 0xee6c4d),
        "S": Color(rgb: 0xf4c7a1),
        "s": Color(rgb: 0xe2a882),
        "E": Color(rgb: 0x1b1630),
        "W": Color(rgb: 0xffffff),
        "M": Color(rgb: 0xc0504d),
        "C": Color(rgb: 0xee6c4d),
        "c": Color(rgb: 0xc9553b),
        "N": Color(rgb: 0x2e4460),
        "B": Color(rgb: 0xf2f2f2),
        "G": Color(rgb: 0xc9dfae),
        "g": Color(rgb: 0xa9c78c),
        "D": Color(rgb: 0x5ab0e6),
        "Z": Color(rgb: 0xffffff),
    ]
    static let quieta: [String] = [
        "..........KKKK..........",
        ".........KHhhHK.........",
        "........KHHhHHHK........",
        "........KHhHHHHK........",
        "........KHHHHHHK........",
        "........KppppppK........",
        "......KKHHHHHHHHKK......",
        ".....KHHhhHHHHHHHHK.....",
        "....KHHhhHHHHHHHHHHK....",
        "...KPKHHHHHHHHHHHHKPK...",
        "..KPpKHHSSSSSSSSHHKpPK..",
        "..KPpKHSSSSSSSSSSHKpPK..",
        "..KPpKSSEESSSSEESSKpPK..",
        "..KPpKSSEWSSSSEWSSKpPK..",
        "..KPPKSsSSSSSSSSsSKPPK..",
        "...KKKSSSSSMMSSSSSKKK...",
        ".....KSSSSSSSSSSSSK.....",
        "......KKSSSSSSSSKK......",
        "........KKSSSSKK........",
        "..........KSSK..........",
        "........KKCCCCKK........",
        ".......KCCCCCCCCCCK.....",
        "......KCCCCCCCCCCCCK....",
        ".....KCCKCCCCCCCCKCCK...",
        ".....KCCKCCCCCCCCKCCK...",
        ".....KCCKCCCCCCCCKCCK...",
        ".....KSSKccccccccKSSK...",
        "......KK.KNNNNNNK.KK....",
        ".........KNNKKNNK.......",
        ".........KNNK.KNNK......",
        ".........KNNK.KNNK......",
        "........KBBBK.KBBBK.....",
        "........KKKKK.KKKKK.....",
    ]
}

// Pose de un cuadro de la animación: hacia dónde miran los ojos y hacia dónde se corre el cuerpo (-1, 0 o 1 pixel).
struct Pose: Equatable {
    var ojos = 0
    var cuerpo = 0
}

extension Sprites {
    // Filas de los ojos y última fila que se balancea (de ahí para abajo, las piernas quedan fijas).
    static let filasOjos = 12...13
    static let ultimaFilaCuerpo = 27

    static func cuadro(_ pose: Pose) -> [String] {
        quieta.enumerated().map { y, fila in
            var f = fila
            if filasOjos.contains(y) { f = correr(f, pose.ojos, desde: 6, hasta: 18, relleno: "S") }
            if y <= ultimaFilaCuerpo { f = correr(f, pose.cuerpo, desde: 0, hasta: 24, relleno: ".") }
            return f
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

    // Secuencia en pasos de 0,25 s: quieta un rato, mira a un lado, se balancea, mira al otro...
    static let secuencia: [(Pose, Int)] = [
        (Pose(), 14), (Pose(ojos: -1), 6), (Pose(), 5),
        (Pose(cuerpo: -1), 3), (Pose(), 2), (Pose(cuerpo: 1), 3), (Pose(), 10),
        (Pose(ojos: 1), 7), (Pose(), 4), (Pose(ojos: -1, cuerpo: -1), 4), (Pose(), 12),
        (Pose(cuerpo: 1), 3), (Pose(), 2), (Pose(cuerpo: -1), 3), (Pose(), 2), (Pose(ojos: 1, cuerpo: 1), 5), (Pose(), 9),
    ]
    static let paso = 0.25

    static func pose(en fecha: Date) -> Pose {
        let total = secuencia.reduce(0) { $0 + $1.1 }
        var resto = Int(fecha.timeIntervalSinceReferenceDate / paso) % total
        for (pose, pasos) in secuencia {
            if resto < pasos { return pose }
            resto -= pasos
        }
        return Pose()
    }
}

// La personita dibujada a 1,5 pt por pixel (3 px exactos en pantallas Retina), sin suavizado.
struct Monito: View {
    var pose = Pose()
    @Environment(\.displayScale) private var escala

    var body: some View {
        Canvas { ctx, _ in
            let t: CGFloat = 1.5
            // Redondea a pixeles del dispositivo para que los bordes queden nítidos.
            let r = { (v: CGFloat) in (v * escala).rounded() / escala }
            for (y, fila) in Sprites.cuadro(pose).enumerated() {
                for (x, letra) in fila.enumerated() {
                    guard let color = Sprites.paleta[letra] else { continue }
                    // La columna 0 y la 23 siempre quedan vacías (aun balanceándose), así que no se dibujan.
                    let x0 = r(CGFloat(x - 1) * t), y0 = r(CGFloat(y) * t)
                    ctx.fill(Path(CGRect(x: x0, y: y0, width: r(CGFloat(x) * t) - x0, height: r(CGFloat(y + 1) * t) - y0)), with: .color(color))
                }
            }
        }
        .frame(width: 33, height: 49.5)
    }
}
