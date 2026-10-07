//
//  EnumColor.swift
//  PhotoCapture
//
//  Created by Omar Hernandez Gonzalez on 06/06/23.
//  Copyright © 2023 Nitin A. All rights reserved.
//

import UIKit

enum Themes: String, CaseIterable {
    case black3
    case darkGray
    case lightGray2
    case white
    case white1
    case gray
    case red
    case green
    case blue
    case cyan
    case yellow
    case magenta
    case orange
    case purple
    case brown
    case clear
    case xclear
    
    var colors: ThemeModel {
        switch self {
        case .black3:
            return ThemeModel(backgound: .systemYellow,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .darkGray:
            return ThemeModel(backgound: .systemYellow,
                              buttonBackGound: .systemBackground,
                              textColor: .label,
                              imageColor: .systemBackground)
        case .lightGray2:
            return ThemeModel(backgound: .systemYellow,
                              buttonBackGound: .label,
                              textColor: .systemBackground,
                              imageColor: .label)
        case .white:
            return ThemeModel(backgound: .systemGreen,
                              buttonBackGound: .systemGray3,
                              textColor: .label,
                              imageColor: .systemGray3)
        case .white1:
            return ThemeModel(backgound: .systemGreen,
                              buttonBackGound: .darkGray,
                              textColor: .label,
                              imageColor: .darkGray)
        case .gray:
            return ThemeModel(backgound: .systemGreen,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .red:
            return ThemeModel(backgound: .systemGreen,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .green:
            return ThemeModel(backgound: .systemRed,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .blue:
            return ThemeModel(backgound: .systemRed,
                              buttonBackGound: .systemBackground,
                              textColor: .label,
                              imageColor: .systemBackground)
        case .cyan:
            return ThemeModel(backgound: .systemRed,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .yellow:
            return ThemeModel(backgound: .systemRed,
                              buttonBackGound: .systemBackground,
                              textColor: .label,
                              imageColor: .systemBackground)
        case .magenta:
            return ThemeModel(backgound: .systemOrange,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .orange:
            return ThemeModel(backgound: .systemOrange,
                              buttonBackGound: .lightGray,
                              textColor: .systemGray,
                              imageColor: .lightGray)
        case .purple:
            return ThemeModel(backgound: .systemOrange,
                              buttonBackGound: .systemGray3,
                              textColor: .systemGray,
                              imageColor: .systemGray3)
        case .brown:
            return ThemeModel(backgound: .systemBlue,
                              buttonBackGound: .systemGray,
                              textColor: .systemBackground,
                              imageColor: .systemGray)
        case .clear:
            return ThemeModel(backgound: .systemBlue,
                              buttonBackGound: .systemBackground,
                              textColor: .systemGray,
                              imageColor: .systemBackground)
        case .xclear:
            return ThemeModel(backgound: .systemBackground,
                              buttonBackGound: UIColor(named: "BGButton") ?? .systemGray5,
                              buttonBackGound2: UIColor(named: "BGButton2") ?? .systemGray3,
                              textColor: .label,
                              imageColor: UIColor(named: "BGButton") ?? .systemGray5)
        }
    }
}

struct ThemeModel {
    /// Color de la vista
    let backgound: UIColor
    /// Color de boton
    let buttonBackGound: UIColor
    /// Color de boton presionado
    let buttonBackGound2: UIColor
    /// Color de texto de la vista
    let textColor: UIColor
    /// Color de texto de la vista
    let imageColor: UIColor
    
    init(backgound: UIColor,
         buttonBackGound: UIColor,
         buttonBackGound2: UIColor = .systemGray3,
         textColor: UIColor,
         imageColor: UIColor = .white) {
        self.backgound = backgound
        self.buttonBackGound = buttonBackGound
        self.buttonBackGound2 = buttonBackGound2
        self.textColor = textColor
        self.imageColor = imageColor
    }
}

extension Themes {
    func resolvedColors(for traits: UITraitCollection?) -> ThemeModel {
        let base = colors
        guard let traits else { return base }
        return ThemeModel(
            backgound: base.backgound.resolvedColor(with: traits),
            buttonBackGound: base.buttonBackGound.resolvedColor(with: traits),
            buttonBackGound2: base.buttonBackGound2.resolvedColor(with: traits),
            textColor: base.textColor.resolvedColor(with: traits),
            imageColor: base.imageColor.resolvedColor(with: traits)
        )
    }
}

extension UIColor {
    func resolvedForDialAppearance(_ traits: UITraitCollection?) -> UIColor {
        guard let traits else { return self }
        return resolvedColor(with: traits)
    }
}
