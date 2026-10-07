//
//  ButtonKeyboard.swift
//  PhotoCapture
//
//  Created by Yair Saucedo on 13/12/22.
//  Copyright © 2022 Nitin A. All rights reserved.
//

import UIKit
import AudioToolbox
import MediaPlayer

class ButtonKeyboard: UIView {
    
    @IBInspectable public var digit: String = "" {
        didSet {
            titleLbl.text = digit
        }
    }

    @IBInspectable public var background: UIColor = .systemGray5 {
        didSet {
            backgroundColor = background
        }
    }

    @IBInspectable public var pushBackground: UIColor = .systemGray3

    @IBInspectable public var subTitle: String = "" {
        didSet {
            subTitleLbl.text = subTitle
        }
    }
    
    @IBInspectable public var image: UIImage! {
        didSet {
            backImage.image = image
        }
    }
 
    @IBInspectable public var imageFactorSize: String! {
        didSet {
            imageWidthConstraint = imageWidthConstraint.setMultiplier(multiplier: Double(imageFactorSize) ?? 1.0)
        }
    }
    
    @IBInspectable public var tintImage: UIColor! {
        didSet {
            backImage.tintColor = tintImage
        }
    }
    @IBInspectable public var tintImageClicked: UIColor!

    private var contentView: UIView!

    @IBOutlet weak var backImage: UIImageView!
    @IBOutlet weak var titleLbl: UILabel!
    @IBOutlet weak var subTitleLbl: UILabel!
    @IBOutlet weak var imageWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var indicator: UIView!
    @IBOutlet weak var nextIndicator: UIView!
    @IBOutlet weak var heightConstraint: NSLayoutConstraint!
    @IBOutlet weak var heightNextConstraint: NSLayoutConstraint!

    var tapAction: ((_ value: String) -> Void)?
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    func commonInit() {
        contentView = Bundle.main.loadNibNamed("ButtonKeyboard", owner: self, options: nil)?[0] as? UIView
        contentView.frame = self.bounds
        addSubview(contentView)
        loadStyle()
        addShadow(toView: indicator)
        addShadow(toView: nextIndicator)
    }
    
    func addShadow(toView: UIView) {
        toView.layer.masksToBounds = false
        toView.layer.shadowColor = UIColor.darkGray.cgColor
        toView.layer.shadowOpacity = 0.2
        toView.layer.shadowOffset = .zero
        toView.layer.shadowRadius = 1
        toView.layer.shouldRasterize = true
    }
    
    public convenience init(title: String,
                            subTitle: String) {
        self.init()
        titleLbl.text = title
        subTitleLbl.text = subTitle
    }
    
    func loadStyle() {
        self.backgroundColor = .systemGray5
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        self.addGestureRecognizer(tapGestureRecognizer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if glassView != nil {
            // No layer mask here: it would clip the glass rim and light-mode shadow.
            layer.mask = nil
            contentView.layer.cornerRadius = bounds.width / 2.0
            contentView.layer.masksToBounds = true
        } else {
            let maskLayer = CAShapeLayer()
            let bez = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.width / 2.0)
            maskLayer.path = bez.cgPath
            layer.mask = maskLayer
        }
        updateIndicators()
    }

    /// iOS 26 Phone keys are Liquid Glass circles; the press flash stays on `contentView` above the glass.
    @discardableResult
    func applyGlassIfAvailable(tint: UIColor = ButtonKeyboard.glassKeyTint) -> Bool {
        guard #available(iOS 26.0, *) else {
            return false
        }
        if glassView == nil {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = tint
            let glass = UIVisualEffectView(effect: effect)
            glass.cornerConfiguration = .capsule()
            glass.isUserInteractionEnabled = false
            glass.frame = bounds
            glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            insertSubview(glass, at: 0)
            glassView = glass
            dimsGlyphOnPress = tint === Self.glassKeyTint
            setNeedsLayout()
        }
        backgroundColor = .clear
        background = .clear
        contentView.backgroundColor = .clear
        pushBackground = Self.glassPressed
        indicator.backgroundColor = Self.glassIndicator
        nextIndicator.backgroundColor = Self.glassIndicator
        return true
    }

    private var glassView: UIVisualEffectView?
    private var dimsGlyphOnPress = false

    /// Phone app press: the key swells ~19 %, brightens and its glyph turns gray, then springs back.
    private func animateGlassPress() {
        superview?.bringSubviewToFront(self)
        let glyphViews: [UIView] = dimsGlyphOnPress ? [titleLbl, subTitleLbl, backImage] : []
        UIView.animate(withDuration: 0.08, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: Self.pressScale, y: Self.pressScale)
            self.contentView.backgroundColor = self.pushBackground
            let pressedAlpha = self.traitCollection.userInterfaceStyle == .dark ? Self.pressedGlyphAlphaDark : Self.pressedGlyphAlpha
            glyphViews.forEach { $0.alpha = pressedAlpha }
        } completion: { _ in
            UIView.animate(withDuration: 0.45, delay: 0.12, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = .identity
                self.contentView.backgroundColor = self.background
                glyphViews.forEach { $0.alpha = 1 }
            }
        }
    }

    /// Resolved fill of a glass key, for previews drawn outside the dialer.
    static let glassKeyFill = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 18 / 255, alpha: 1) : UIColor(white: 253 / 255, alpha: 1) }

    private static let pressScale: CGFloat = 1.19
    /// Black glyph at this alpha on the white pressed key gives the measured #B6B6B6.
    private static let pressedGlyphAlpha: CGFloat = 0.29
    /// White glyph over the lit dark key (#414141) gives the measured #D6D6D6.
    private static let pressedGlyphAlphaDark: CGFloat = 0.78

    /// Darkens/lightens the glass to the measured Phone key fill (#121212 dark, #FDFDFD light).
    static let glassKeyTint = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.4) : UIColor(white: 1, alpha: 0.4) }

    private static let glassPressed = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.2) : .white }
    /// Same contrast the white marker had on the gray xclear keys, so it stays subtle on the near-white light glass.
    static let glassIndicator = UIColor { $0.userInterfaceStyle == .dark
        ? .white : UIColor(white: 0.89, alpha: 1) }
    
    func updateIndicators() {
        let indicatorSize: Int = UserDefaults.standard.value(forKey: CarphoneDialKeys.indicatorSize) as? Int ?? 4
        let nextNumberIndicatorSize: Int = UserDefaults.standard.value(forKey: CarphoneDialKeys.nextNumberIndicatorSize) as? Int ?? 4
        heightConstraint.constant = CGFloat(indicatorSize)
        heightNextConstraint.constant = CGFloat(nextNumberIndicatorSize)
    }
    
    func pressButton() {
        playDialNumber(toneID: tag)
        if glassView != nil {
            animateGlassPress()
            tapAction?(titleLbl.text!)
            return
        }
        contentView.backgroundColor = self.pushBackground
        UIView.animate(withDuration: 1.5) { [weak self] in
            self?.contentView.backgroundColor = self?.background
        }
        
        if let imageClicked = backImage, let tintImgClicked = tintImageClicked {
            UIView.animate(withDuration: 0.7) {
                imageClicked.tintColor = tintImgClicked
                imageClicked.tintColor = self.tintImage
            }
        }
        tapAction?(titleLbl.text!)
    }
    
    func playDialNumber(toneID: Int) {
        // Play built-in iPhone DialPad Sound
        let toneID = UInt(1200 + toneID)
        AudioServicesPlaySystemSound(SystemSoundID(toneID))
    }
    
    func configure(theme: Themes) {
        applyTheme(theme.colors, forSnapshot: false)
    }

    func configure(palette: ThemeModel) {
        applyTheme(palette, forSnapshot: false)
    }

    /// Solid fills for off-screen capture — `UIVisualEffectView` glass does not rasterize in snapshots.
    func applySnapshotKeyAppearance() {
        glassView?.removeFromSuperview()
        glassView = nil
        layer.mask = nil
        let fill = UIColor(named: "BGButton") ?? .systemGray5
        backgroundColor = fill
        background = fill
        contentView.backgroundColor = fill
        pushBackground = UIColor(named: "BGButton2") ?? .systemGray3
        titleLbl.textColor = UIColor(named: "Text") ?? .label
        subTitleLbl.textColor = UIColor(named: "Text") ?? .label
        backImage.tintColor = UIColor(named: "Text") ?? .label
        setNeedsLayout()
    }

    func applySnapshotCallAppearance(fill: UIColor) {
        applySnapshotKeyAppearance()
        backgroundColor = fill
        background = fill
        contentView.backgroundColor = fill
    }

    private func applyTheme(_ palette: ThemeModel, forSnapshot: Bool) {
        let work = { [weak self] in
            guard let self else {
                return
            }
            self.backImage.tintColor = palette.textColor
            self.titleLbl.textColor = palette.textColor
            self.subTitleLbl.textColor = palette.textColor
            self.tintImage = palette.textColor
            if forSnapshot {
                self.applySnapshotKeyAppearance()
                return
            }
            if self.applyGlassIfAvailable() {
                return
            }
            self.backgroundColor = palette.buttonBackGound
            self.background = palette.buttonBackGound
            self.contentView.backgroundColor = palette.buttonBackGound
            self.pushBackground = palette.buttonBackGound2
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
    
    @objc private func didTap(_ sender: UITapGestureRecognizer) {
        pressButton()
    }
    
    func showIndicator(value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.indicator.isHidden = !value
        }
    }
    
    func showNextIndicator(value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.nextIndicator.isHidden = !value
        }
    }
}

extension NSLayoutConstraint {
    func setMultiplier(multiplier: CGFloat) -> NSLayoutConstraint {
        guard let firstItem = firstItem else {
            return self
        }
        NSLayoutConstraint.deactivate([self])
        let newConstraint = NSLayoutConstraint(item: firstItem, attribute: firstAttribute, relatedBy: relation, toItem: secondItem, attribute: secondAttribute, multiplier: multiplier, constant: constant)
        newConstraint.priority = priority
        newConstraint.shouldBeArchived = self.shouldBeArchived
        newConstraint.identifier = self.identifier
        NSLayoutConstraint.activate([newConstraint])
        return newConstraint
    }
}
