//
//  PhoneKeyboard.swift
//  PhotoCapture
//
//  Created by Yair Saucedo on 12/12/22.
//  Copyright © 2022 Nitin A. All rights reserved.
//

import UIKit
import AudioToolbox
import MediaPlayer

/// Keypad geometry of the iOS 26 Phone app measured on a 430 × 932 pt screen, scaled to the current one.
struct PhoneKeypadMetrics {
    static let referenceWidth: CGFloat = 430
    static let referenceHeight: CGFloat = 932

    let key: CGFloat
    let callKey: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
    let callGap: CGFloat
    let tabBarGap: CGFloat
    /// Centers below the safe-area top (59 pt on the reference device).
    let numberCenterY: CGFloat
    let addContactCenterY: CGFloat
    let numberFontSize: CGFloat
    let addContactTrailing: CGFloat = 20
    let addContactPointSize: CGFloat = 22
    let asteriskPointSize: CGFloat
    let hashPointSize: CGFloat
    let deletePointSize: CGFloat

    init(screen: CGSize) {
        let widthScale = screen.width / Self.referenceWidth
        let heightScale = min(1, screen.height / Self.referenceHeight)
        key = (88 * widthScale).rounded(.toNearestOrEven)
        callKey = (85 * widthScale).rounded(.toNearestOrEven)
        columnGap = 24 * widthScale
        rowGap = 20 * heightScale
        callGap = 26 * heightScale
        tabBarGap = 62 * heightScale
        /// Slightly lower than the first Carphone port — full-screen cover safe area reads higher on device.
        numberCenterY = 68 * heightScale
        numberFontSize = 36 * min(1, widthScale)
        addContactCenterY = 30 * heightScale
        asteriskPointSize = 20 * widthScale
        hashPointSize = 24 * widthScale
        deletePointSize = 31 * widthScale
    }
}

class PhoneKeyboard: UIView {
    private var contentView: UIView!
    private var nativeLayoutApplied = false
    private let tabBar = PhoneTabBarView()
    private let addContactIcon = UIImageView()
    private lazy var tabBarBottom = tabBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                                   constant: -PhoneTabBarView.Metrics.bottomInset(safeAreaBottom: 0))
    
    @IBOutlet private weak var stackContent: UIStackView!
    @IBOutlet private weak var viewLine1: UIView!
    @IBOutlet private weak var stackLine1: UIStackView!
    @IBOutlet private weak var stackLine2: UIStackView!
    @IBOutlet private weak var stackLine3: UIStackView!
    @IBOutlet private weak var stackLine4: UIStackView!
    @IBOutlet private weak var stackLine5: UIStackView!
    
    @IBOutlet private weak var sixSection: UIView!
    
    @IBOutlet weak var telephoneLbl: UILabel!
    @IBOutlet weak var addNumberLbl: UILabel!
    @IBOutlet weak var backView: UIView!
    
    @IBOutlet weak var oneBtn: ButtonKeyboard!
    @IBOutlet weak var twoBtn: ButtonKeyboard!
    @IBOutlet weak var threeBtn: ButtonKeyboard!
    @IBOutlet weak var fourBtn: ButtonKeyboard!
    @IBOutlet weak var fiveBtn: ButtonKeyboard!
    @IBOutlet weak var sixBtn: ButtonKeyboard!
    @IBOutlet weak var sevenBtn: ButtonKeyboard!
    @IBOutlet weak var eightBtn: ButtonKeyboard!
    @IBOutlet weak var nineBtn: ButtonKeyboard!
    @IBOutlet weak var zeroBtn: ButtonKeyboard!
    @IBOutlet weak var backBtn: ButtonKeyboard!
    @IBOutlet weak var callBtn: ButtonKeyboard!
    @IBOutlet weak var asteriskBtn: ButtonKeyboard!
    @IBOutlet weak var hastashBtn: ButtonKeyboard!
    @IBOutlet weak var callingImg: UIImageView!
    var numberBtnArray:[ButtonKeyboard] = []
    var valueSelected: Int = -1
    var timeElapsed: Int = 0
    var waitTime: Int = 3
    var timer: Timer? = nil
    var pressCallButton: (() -> Void) = {}
    var touchBottomLeft: (() -> Void) = {}
    var buttonPressed: ((String) -> Void)?
    var format = ""
    var isReverse: Bool = false
    var possibleNumber: String = ""
    var telephoneDidChange: ((_ oldValue: String, _ newValue: String) -> Void)?
    var telephone: String = "" {
        didSet {
            scheduleTelephoneDisplayRefresh(animated: true)
            telephoneDidChange?(oldValue, telephone)
        }
    }

    /// Updates the number field immediately (used before dial snapshots; avoids async `didSet` races).
    func syncTelephoneDisplay(animated: Bool = false) {
        scheduleTelephoneDisplayRefresh(animated: animated)
    }

    private func scheduleTelephoneDisplayRefresh(animated: Bool) {
        let work = { [weak self] in
            guard let self else {
                return
            }
            let formatted: String
            if self.isReverse {
                formatted = self.configureFormat(
                    phone: self.telephone,
                    format: self.getFormat(phone: self.possibleNumber)
                )
            } else {
                formatted = CarphoneDialFormat.liveDisplay(self.telephone)
            }
            self.telephoneLbl.attributedText = self.displayText(formatted)
            let show = !self.telephone.isEmpty
            let apply = {
                self.backView.layer.opacity = show ? 1.0 : 0.0
                self.addNumberLbl.layer.opacity = show ? 1.0 : 0.0
                self.addContactIcon.alpha = show ? 1 : 0
            }
            if animated {
                UIView.animate(withDuration: 0.3, animations: apply)
            } else {
                apply()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
    
    func getFormat(phone: String) -> String {
        var newFormat = format
        var phoneAux = phone

        if phoneAux.count <= format.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
            .count {
            var auxNewFormat = ""
            var add = 0
            while auxNewFormat.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "-", with: "")
                .count != phoneAux.count {
                newFormat = String(format.suffix(phoneAux.count+add))
                auxNewFormat = newFormat
                add+=1
            }
        }
        return validateParentesis(string: newFormat)
    }
    
    func validateParentesis(string: String) -> String {
        var newFormat = string
        let openParentesis: Bool = string.contains("(")
        let closeParentesis: Bool = string.contains(")")
        let variable = (openParentesis, closeParentesis)
        switch variable {
        case (true, false):
            let index = String.Index.init(utf16Offset: newFormat.count, in: newFormat)
            newFormat.insert(")", at: index)
        case (false, true):
            let index = String.Index.init(utf16Offset: 0, in: newFormat)
            newFormat.insert("(", at: index)
        default:
            break
        }
        print(newFormat)
        return newFormat
    }

    func configureFormat(phone: String, format: String) -> String {
        if format != "" {
            let newFormat = format
            var phoneAux = phone

            if isReverse {
                for (i, char) in newFormat.reversed().enumerated() {
                    if char.lowercased() != "x" {
                        if phoneAux.count > i {
                            let index = String.Index.init(utf16Offset: phoneAux.count-i, in: phoneAux)
                            phoneAux.insert(char, at: index)
                        }
                    }
                }
                return validateParentesis(string: phoneAux)
            } else {
                for (i, char) in newFormat.enumerated() {
                    if char.lowercased() != "x" {
                        if phoneAux.count > i {
                            let index = String.Index.init(utf16Offset: i, in: phoneAux)
                            phoneAux.insert(char, at: index)
                        }
                    }
                }
                return validateParentesis(string: phoneAux)
            }
        } else {
            return phone
        }
    }
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            themeFromDefaults()
        }
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            applyLocalizedAddNumberCaption()
        }
    }

    func applyLocalizedAddNumberCaption() {
        let key = "dialer.add_number_caption"
        let localized = NSLocalizedString(
            key,
            tableName: "CarphoneDialLocalizable",
            bundle: .main,
            value: "Add Number",
            comment: "Caption under the dialed number on the in-app Phone keypad"
        )
        addNumberLbl.text = localized
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @IBAction func tapBottomLeft(_ sender: Any) {
       
    }
    
    func commonInit() {
        contentView = Bundle.main.loadNibNamed("PhoneKeyboard", owner: self, options: nil)?[0] as? UIView
        contentView.frame = self.bounds
        addSubview(contentView)
        telephoneLbl.text = ""
        applyLocalizedAddNumberCaption()
        oneBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        twoBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        threeBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        fourBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        fiveBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        sixBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        sevenBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        eightBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        nineBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        zeroBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            let backSpacePressed = UserDefaults.standard.bool(forKey: CarphoneDialKeys.backSpacePressed)
            if backSpacePressed {
                UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
                self.digitPressed(value: value)
            } else {
                self.buttonPressed?(value)
            }
        }
        backBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            if !self.telephone.isEmpty {
                self.telephone.removeLast()
            }
            UserDefaults.standard.set(true, forKey: CarphoneDialKeys.backSpacePressed)
            self.valueSelected = -1
            self.timeElapsed = 0
            self.timer = Timer.scheduledTimer(timeInterval: 1.0,
                                              target: self,
                                              selector: #selector(self.validateTime),
                                              userInfo: nil,
                                              repeats: true)
        }
        
        callBtn.tapAction = { [weak self] (_ value: String) in
            guard let self = self else {
                return
            }
            self.pressCall()
        }
        
        loadStyle()
        numberBtnArray.append(oneBtn)
        numberBtnArray.append(twoBtn)
        numberBtnArray.append(threeBtn)
        numberBtnArray.append(fourBtn)
        numberBtnArray.append(fiveBtn)
        numberBtnArray.append(sixBtn)
        numberBtnArray.append(sevenBtn)
        numberBtnArray.append(eightBtn)
        numberBtnArray.append(nineBtn)
        numberBtnArray.append(zeroBtn)
        themeFromDefaults()
    }

    /// Lays out keypad and tab bar like the Phone app; `stackContent` is pinned to the safe-area top in the xib.
    private func applyNativeLayout() {
        let layoutSize = bounds.height >= 400 && bounds.width >= 200 ? bounds.size : UIScreen.main.bounds.size
        let metrics = PhoneKeypadMetrics(screen: layoutSize)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(tabBar, belowSubview: callingImg)

        let callRow: UIView = sixSection
        let lastKeyRow: UIView = stackLine4.superview ?? stackLine4
        let keyRows: [UIView] = [viewLine1, stackLine2.superview, stackLine3.superview, lastKeyRow].compactMap { $0 }

        stackContent.spacing = metrics.rowGap
        stackContent.setCustomSpacing(metrics.callGap, after: lastKeyRow)
        for line in [stackLine1, stackLine2, stackLine3, stackLine4] {
            line?.spacing = metrics.columnGap
        }
        // Keeps the delete key on the third column even though the call row is slightly shorter.
        stackLine5.spacing = metrics.columnGap + (metrics.key - metrics.callKey)

        // Pin the keypad from the tab bar upward — a top spacer + safe-area top pin clips rows off-screen.
        deactivateStackTopPinIfNeeded()
        telephoneLbl.removeFromSuperview()
        telephoneLbl.translatesAutoresizingMaskIntoConstraints = false
        displayFont = .systemFont(ofSize: metrics.numberFontSize)
        telephoneLbl.font = displayFont
        telephoneLbl.adjustsFontSizeToFitWidth = true
        telephoneLbl.minimumScaleFactor = 0.5
        contentView.insertSubview(telephoneLbl, belowSubview: callingImg)

        addContactIcon.image = UIImage(systemName: "person.crop.circle.badge.plus",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: metrics.addContactPointSize))
        addContactIcon.tintColor = .label
        addContactIcon.alpha = telephone.isEmpty ? 0 : 1
        addContactIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(addContactIcon, belowSubview: callingImg)

        setSymbol(on: asteriskBtn, name: "asterisk", pointSize: metrics.asteriskPointSize, weight: .semibold)
        setSymbol(on: hastashBtn, name: "number", pointSize: metrics.hashPointSize, weight: .medium)
        backBtn.image = UIImage(systemName: "delete.left.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: metrics.deletePointSize, weight: .medium)
                                    .applying(UIImage.SymbolConfiguration(paletteColors: [.label, .systemGray5])))
        backBtn.backImage.contentMode = .center
        backBtn.tintImage = nil
        backBtn.tintImageClicked = nil

        let safeTop = contentView.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            telephoneLbl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            telephoneLbl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            telephoneLbl.centerYAnchor.constraint(equalTo: safeTop, constant: metrics.numberCenterY),
            addNumberLbl.centerYAnchor.constraint(equalTo: telephoneLbl.centerYAnchor, constant: 36),
            addContactIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -metrics.addContactTrailing),
            addContactIcon.centerYAnchor.constraint(equalTo: safeTop, constant: metrics.addContactCenterY)
        ])

        stackContent.setContentCompressionResistancePriority(.required, for: .vertical)
        for row in keyRows + [callRow] {
            row.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        NSLayoutConstraint.activate(keyRows.map { $0.heightAnchor.constraint(equalToConstant: metrics.key) } + [
            callRow.heightAnchor.constraint(equalToConstant: metrics.callKey),
            stackContent.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -metrics.tabBarGap),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: PhoneTabBarView.Metrics.sideInset),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -PhoneTabBarView.Metrics.sideInset),
            tabBar.heightAnchor.constraint(equalToConstant: PhoneTabBarView.Metrics.height),
            tabBarBottom
        ])
    }

    private func deactivateStackTopPinIfNeeded() {
        let candidates = contentView.constraints + (contentView.superview?.constraints ?? [])
        for constraint in candidates {
            let involvesStack = (constraint.firstItem as? UIStackView) === stackContent
                || (constraint.secondItem as? UIStackView) === stackContent
            guard involvesStack else {
                continue
            }
            if constraint.firstAttribute == .top || constraint.secondAttribute == .top {
                constraint.isActive = false
            }
        }
    }

    private var displayFont = UIFont.systemFont(ofSize: 37)

    /// SF Pro draws `*` small and raised; the Phone display shows it digit-sized and centered on the digits.
    private func displayText(_ string: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for character in string {
            if character == "*", let asterisk = asteriskAttachment() {
                result.append(NSAttributedString(attachment: asterisk))
            } else {
                result.append(NSAttributedString(string: String(character), attributes: [.font: displayFont]))
            }
        }
        return result
    }

    private func asteriskAttachment() -> NSTextAttachment? {
        let size = displayFont.pointSize * Self.asteriskHeight
        guard let image = UIImage(systemName: "asterisk",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)) else {
            return nil
        }
        let attachment = NSTextAttachment(image: image.withRenderingMode(.alwaysTemplate))
        let digitCenter = displayFont.capHeight / 2
        attachment.bounds = CGRect(x: 0, y: digitCenter - image.size.height / 2,
                                   width: image.size.width, height: image.size.height)
        return attachment
    }

    /// Symbol point size relative to the display font, giving the measured 16 × 17 pt asterisk at 36 pt.
    private static let asteriskHeight: CGFloat = 0.48

    private func setSymbol(on button: ButtonKeyboard, name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        button.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
        button.backImage.contentMode = .center
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        tabBarBottom.constant = -PhoneTabBarView.Metrics.bottomInset(safeAreaBottom: safeAreaInsets.bottom)
    }
    
    @objc func validateTime() {
        print(timeElapsed)
        timeElapsed+=1
    }
    
    func loadStyle() {
        self.backView.layer.opacity = 0.0
        self.addNumberLbl.layer.opacity = 0.0
        self.callingImg.isHidden = true
    }
    
    func configureColor(theme: Themes, forSnapshot: Bool = false, resolvedWith traits: UITraitCollection? = nil) {
        let applyChrome = { [weak self] in
            guard let self else {
                return
            }
            let background = theme.colors.backgound.resolvedForDialAppearance(traits)
            let text = theme.colors.textColor.resolvedForDialAppearance(traits)
            self.backgroundColor = background
            self.contentView.backgroundColor = background
            self.telephoneLbl.textColor = text
            self.addNumberLbl.textColor = text.withAlphaComponent(0.55)
        }
        if Thread.isMainThread {
            applyChrome()
        } else {
            DispatchQueue.main.sync(execute: applyChrome)
        }

        let palette = theme.resolvedColors(for: traits)
        for button in numberBtnArray {
            if forSnapshot {
                button.applySnapshotKeyAppearance()
            } else {
                button.configure(palette: palette)
            }
        }
        if forSnapshot {
            asteriskBtn.applySnapshotKeyAppearance()
            hastashBtn.applySnapshotKeyAppearance()
            callBtn.applySnapshotCallAppearance(fill: Self.callGreen)
        } else {
            asteriskBtn.configure(palette: palette)
            hastashBtn.configure(palette: palette)
            if !callBtn.applyGlassIfAvailable(tint: Self.callGreen) {
                callBtn.background = Self.callGreen
                callBtn.pushBackground = Self.callGreenPressed
            }
        }
    }

    /// Call key green of the iOS 26 Phone keypad.
    private static let callGreen = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 56 / 255, green: 120 / 255, blue: 55 / 255, alpha: 1)
        : UIColor(red: 106 / 255, green: 205 / 255, blue: 108 / 255, alpha: 1) }
    private static let callGreenPressed = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 86 / 255, green: 150 / 255, blue: 85 / 255, alpha: 1)
        : UIColor(red: 76 / 255, green: 175 / 255, blue: 78 / 255, alpha: 1) }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        guard bounds.width >= 200, bounds.height >= 400, !nativeLayoutApplied else {
            return
        }
        nativeLayoutApplied = true
        applyNativeLayout()
        setNeedsLayout()
    }

    /// Ensures native keypad layout and theme are ready before off-screen capture.
    func prepareForSnapshotRender() {
        if !nativeLayoutApplied, bounds.width >= 200, bounds.height >= 400 {
            nativeLayoutApplied = true
            applyNativeLayout()
        }
        configureColor(theme: .xclear, forSnapshot: true)
        syncTelephoneDisplay(animated: false)
        contentView.clipsToBounds = false
        clipsToBounds = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    #if DEBUG
    var debugLayoutSummary: String {
        let one = oneBtn?.frame ?? .zero
        return "native=\(nativeLayoutApplied) bounds=\(bounds.integral) stack=\(stackContent.frame.integral) oneBtn=\(one.integral)"
    }
    #endif
    
    func nextDigit(digit: String) {
        var digitInt = 0
        switch digit {
        case "0":
            digitInt = 10
        case "1":
            digitInt = 1
        case "2":
            digitInt = 2
        case "3":
            digitInt = 3
        case "4":
            digitInt = 4
        case "5":
            digitInt = 5
        case "6":
            digitInt = 6
        case "7":
            digitInt = 7
        case "8":
            digitInt = 8
        case "9":
            digitInt = 9
        default:
            for btn in numberBtnArray {
                btn.showNextIndicator(value: false)
            }
            return
        }
        for btn in numberBtnArray {
            btn.showNextIndicator(value: btn.tag == digitInt)
        }
    }
    
    func pressDigit(digit: String) {
        switch digit {
        case "0":
            zeroBtn.pressButton()
        case "1":
            oneBtn.pressButton()
        case "2":
            twoBtn.pressButton()
        case "3":
            threeBtn.pressButton()
        case "4":
            fourBtn.pressButton()
        case "5":
            fiveBtn.pressButton()
        case "6":
            sixBtn.pressButton()
        case "7":
            sevenBtn.pressButton()
        case "8":
            eightBtn.pressButton()
        case "9":
            nineBtn.pressButton()
        case "+":
            buttonPressed?("+")
        default:
            print("other")
        }
    }
    
    func pressAllDigits(number: String) {
        telephone = number
    }
    
    func pressCall(copy: Bool = true) {
        //telephoneLbl.textColor = .white
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // your code here
            //self?.telephoneLbl.textColor = .black
            if copy {
                self?.pressCallButton()
            }
        }
    }
    
    func digitPressed(value: String) {
        
        let reverse = UserDefaults.standard.value(forKey: CarphoneDialKeys.reverse) as? Bool ?? false
        if reverse {
            var separate = telephone.components(separatedBy: "")
            separate.insert(value, at: 0)
            telephone = separate.joined()
        } else {
            telephone.append(value)
        }
    }
    
    func volumePressed() {
        if timeElapsed >= waitTime, valueSelected != -1 {
            handPositionFound()
        } else {
            if valueSelected == -1 {
                valueSelected = 1
            } else {
                valueSelected+=1
                if valueSelected == 11  {
                    valueSelected = 1
                }
            }
            for btn in numberBtnArray {
                btn.showIndicator(value: btn.tag == valueSelected)
            }
        }
        timeElapsed = 0
    }
    
    func handPositionFound() {
        UserDefaults.standard.set(false, forKey: CarphoneDialKeys.backSpacePressed)
        timer?.invalidate()
        timer = nil
        guard let button = numberBtnArray.first(where: { $0.tag == valueSelected }) else {
            return
        }
        button.showIndicator(value: false)
        button.pressButton()
    }
    
    func applyDialSystemInterfaceStyle(_ style: UIUserInterfaceStyle, background: UIColor) {
        overrideUserInterfaceStyle = style
        contentView.overrideUserInterfaceStyle = style
        contentView.backgroundColor = background
    }

    func themeFromDefaults(resolvedWith traits: UITraitCollection? = nil) {
        UserDefaults.standard.set(Themes.xclear.rawValue, forKey: CarphoneDialKeys.theme)
        configureColor(theme: .xclear, resolvedWith: traits)
        for btn in numberBtnArray {
            btn.updateIndicators()
        }
    }
    
    func playDialNumber(toneID: Int) {
        // Play built-in iPhone DialPad Sound
        let toneID = UInt(1200 + toneID)
        AudioServicesPlaySystemSound(SystemSoundID(toneID))
    }
}
