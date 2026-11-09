import UIKit

@main
final class HarnessApp: UIResponder, UIApplicationDelegate, UITextViewDelegate {
  var window: UIWindow?
  private var events: [[String: Any]] = []
  private var report: [String: Any] = [:]
  private var selectionView: NativeSelectionView!
  private var referenceView: UITextView?
  private var rangeLabel: UILabel!
  private var dragLabel: UILabel!
  private var selectedTextLabel: UILabel!
  private var nativeClasses: Set<String> = []
  private var timer: Timer?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let controller = UIViewController()
    controller.view.frame = window.bounds
    controller.view.backgroundColor = .white
    controller.view.semanticContentAttribute = HarnessCanvas.rtl ? .forceRightToLeft : .forceLeftToRight
    let canvas = HarnessCanvas(frame: controller.view.bounds)
    canvas.backgroundColor = .white
    canvas.isHidden = HarnessCanvas.reference
    canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view.addSubview(canvas)
    selectionView = NativeSelectionView(frame: controller.view.bounds)
    selectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    selectionView.accessibilityIdentifier = "native-selection"
    if HarnessCanvas.reference {
      let reference = UITextView(frame: CGRect(x: 24, y: 160, width: window.bounds.width - 48, height: 240))
      reference.isEditable = false
      reference.isSelectable = true
      reference.isScrollEnabled = false
      reference.textContainerInset = .zero
      reference.textContainer.lineFragmentPadding = 0
      reference.attributedText = HarnessCanvas.attributedText
      reference.delegate = self
      reference.semanticContentAttribute = .forceRightToLeft
      reference.tintColor = UIColor(red: 26 / 255, green: 115 / 255, blue: 232 / 255, alpha: 1)
      referenceView = reference
      controller.view.addSubview(reference)
    } else {
      controller.view.addSubview(selectionView)
    }
    rangeLabel = UILabel(frame: CGRect(x: 40, y: 500, width: window.bounds.width - 80, height: 50))
    rangeLabel.accessibilityIdentifier = "range"
    rangeLabel.text = "\(HarnessCanvas.initialBase):\(HarnessCanvas.initialExtent)"
    rangeLabel.textColor = .black
    controller.view.addSubview(rangeLabel)
    let reset = UIButton(type: .system)
    reset.frame = CGRect(x: 40, y: 560, width: 120, height: 48)
    reset.setTitle("Reset", for: .normal)
    reset.accessibilityIdentifier = "reset"
    reset.addTarget(self, action: #selector(resetSelection), for: .touchUpInside)
    controller.view.addSubview(reset)
    dragLabel = UILabel(frame: CGRect(x: 40, y: 620, width: window.bounds.width - 80, height: 50))
    dragLabel.textColor = .black
    dragLabel.text = "not-started"
    dragLabel.accessibilityIdentifier = "drag-events"
    controller.view.addSubview(dragLabel)
    let preview = UIButton(type: .system)
    preview.frame = CGRect(x: 40, y: 680, width: 160, height: 48)
    preview.setTitle("Preview", for: .normal)
    preview.accessibilityIdentifier = "preview"
    preview.addTarget(self, action: #selector(previewSelection), for: .touchUpInside)
    controller.view.addSubview(preview)
    selectedTextLabel = UILabel(frame: CGRect(x: 24, y: 740, width: window.bounds.width - 48, height: 50))
    selectedTextLabel.textColor = .black
    selectedTextLabel.numberOfLines = 2
    selectedTextLabel.text = (HarnessCanvas.text as NSString).substring(with: NSRange(location: HarnessCanvas.initialBase, length: HarnessCanvas.initialExtent - HarnessCanvas.initialBase))
    selectedTextLabel.accessibilityIdentifier = "selected-text"
    controller.view.addSubview(selectedTextLabel)
    let geometry = SelectionGeometry(text: HarnessCanvas.text, boxes: HarnessCanvas.boxes)
    let endCaret = geometry.caret(at: HarnessCanvas.initialExtent, preferPrevious: true)
    let targetCaret = geometry.caret(at: 13, preferPrevious: true)
    let edges = UILabel(frame: CGRect(x: 24, y: 800, width: window.bounds.width - 48, height: 50))
    edges.font = .systemFont(ofSize: 10)
    edges.textColor = .black
    edges.accessibilityIdentifier = "edges"
    edges.text = "\(endCaret.minX + 0.5),\(endCaret.midY);\(targetCaret.minX + 0.5),\(endCaret.midY)"
    controller.view.addSubview(edges)
    selectionView.onEvent = { [weak self] name, values in
      guard let self else { return }
      let recognizers: [UIGestureRecognizer] = self.selectionView.gestureRecognizers ?? []
      self.events.append([
        "name": name, "values": values,
        "activeGestures": recognizers.filter { $0.state == .began || $0.state == .changed }.map { String(describing: type(of: $0)) }
      ])
      if name == "selectionChanged" {
        self.rangeLabel.text = "\(values["base"]!):\(values["extent"]!)"
        self.selectedTextLabel.text = self.selectionView.selectedTextRange.flatMap { self.selectionView.text(in: $0) }
        if self.dragLabel.text == "finished" { self.dragLabel.text = "range-after-finish" }
      }
      if name == "adjusting", values["value"] as? Bool == true {
        self.dragLabel.text = "started"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
          guard let self, let window = self.window,
            let document = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
          else { return }
          let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            for snapshotWindow in UIApplication.shared.windows {
              snapshotWindow.drawHierarchy(in: snapshotWindow.bounds, afterScreenUpdates: true)
            }
          }
          try? image.pngData()?.write(to: document.appendingPathComponent("native-selection-adjusting.png"))
        }
      }
      if name == "adjusting", values["value"] as? Bool == false, self.dragLabel.text == "started" {
        self.dragLabel.text = "finished"
      }
      self.writeReport()
    }
    report["interactionClass"] = String(describing: type(of: selectionView.interactions.first!))
    selectionView.update([
      "revision": 1,
      "text": HarnessCanvas.text,
      "boxes": HarnessCanvas.boxes,
      "selection": ["base": HarnessCanvas.initialBase, "extent": HarnessCanvas.initialExtent],
      "accent": UInt32(0xff1a73e8),
      "selectionColor": UInt32(0x441a73e8),
      "showMenu": false
    ])
    self.window = window
    window.rootViewController = controller
    window.makeKeyAndVisible()
    if let referenceView {
      referenceView.becomeFirstResponder()
      referenceView.selectedRange = NSRange(location: 0, length: HarnessCanvas.initialExtent)
      let end = referenceView.position(from: referenceView.beginningOfDocument, offset: HarnessCanvas.initialExtent)!
      let target = referenceView.position(from: referenceView.beginningOfDocument, offset: 13)!
      let endCaret = referenceView.caretRect(for: end).offsetBy(dx: 24, dy: 160)
      let targetCaret = referenceView.caretRect(for: target).offsetBy(dx: 24, dy: 160)
      edges.text = "\(endCaret.minX + 0.5),\(endCaret.midY);\(targetCaret.minX + 0.5),\(endCaret.midY)"
      report["referenceEndCaret"] = String(describing: endCaret)
      report["referenceTargetCaret"] = String(describing: targetCaret)
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self else { return }
      for window in UIApplication.shared.windows { self.collect(window) }
      self.writeReport()
    }
    return true
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    let range = textView.selectedRange
    rangeLabel?.text = "\(range.location):\(NSMaxRange(range))"
    selectedTextLabel?.text = (textView.text as NSString).substring(with: range)
    events.append(["name": "referenceSelectionChanged", "values": ["base": range.location, "extent": NSMaxRange(range)]])
    if selectionView != nil { writeReport() }
  }

  @objc private func resetSelection() {
    selectionView.select(base: HarnessCanvas.initialBase, extent: HarnessCanvas.initialExtent, notify: false)
    rangeLabel.text = "\(HarnessCanvas.initialBase):\(HarnessCanvas.initialExtent)"
  }

  @objc private func previewSelection() {
    let range = selectionView.selectedTextRange as! NativeTextRange
    selectionView.update([
      "revision": 2,
      "text": HarnessCanvas.text,
      "boxes": HarnessCanvas.boxes,
      "selection": ["base": range.base, "extent": range.extent],
      "accent": UInt32(0xff1a73e8),
      "selectionColor": UInt32(0x66ffb300),
      "showMenu": false
    ])
  }

  private func collect(_ view: UIView) {
    let name = String(describing: type(of: view))
    if !view.isHidden, view.alpha > 0 {
      nativeClasses.insert(name)
    }
    for child in view.subviews { collect(child) }
  }

  private func writeReport() {
    report["events"] = events
    report["rtl"] = HarnessCanvas.rtl
    report["reference"] = HarnessCanvas.reference
    report["customInput"] = inputGeometry(selectionView)
    if let referenceView { report["referenceInput"] = inputGeometry(referenceView) }
    report["text"] = HarnessCanvas.text
    report["selectedText"] = referenceView.map { ($0.text as NSString).substring(with: $0.selectedRange) }
      ?? selectionView.selectedTextRange.flatMap { selectionView.text(in: $0) }
    report["visibleNativeClasses"] = nativeClasses.sorted()
    report["isFirstResponder"] = selectionView.isFirstResponder
    report["inputDelegate"] = selectionView.inputDelegate.map { String(describing: type(of: $0)) } ?? "nil"
    report["interactions"] = selectionView.interactions.map { String(describing: type(of: $0)) }
    report["viewFrame"] = String(describing: selectionView.frame)
    let recognizers: [UIGestureRecognizer] = selectionView.gestureRecognizers ?? []
    report["gestureRecognizers"] = recognizers.map {
      ["class": String(describing: type(of: $0)), "pan": $0 is UIPanGestureRecognizer, "longPress": $0 is UILongPressGestureRecognizer]
    }
    report["hitTest"] = selectionView.hitTest(CGPoint(x: 80, y: 178), with: nil).map { String(describing: type(of: $0)) } ?? "nil"
    report["keyboardInputViewHeight"] = selectionView.inputView?.frame.height ?? -1
    guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
      let document = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    try? data.write(to: document.appendingPathComponent("native-selection-report.json"))
    try? data.write(to: document.appendingPathComponent("native-selection-report-\(ProcessInfo.processInfo.processIdentifier).json"))
  }

  private func inputGeometry(_ input: UIView & UITextInput) -> [String: Any] {
    guard let end = input.position(from: input.beginningOfDocument, offset: HarnessCanvas.initialExtent),
      let range = input.textRange(from: input.beginningOfDocument, to: end)
    else { return [:] }
    var result: [String: Any] = [
      "uiDirection": input.effectiveUserInterfaceLayoutDirection.rawValue,
      "affinity": input.selectionAffinity?.rawValue ?? -1,
      "coordinateViewDirection": input.textInputView?.effectiveUserInterfaceLayoutDirection.rawValue ?? -1,
      "coordinateViewClass": input.textInputView.map { String(describing: type(of: $0)) } ?? "nil",
      "writingDirection": input.baseWritingDirection(for: range.start, in: .forward).rawValue,
      "startCaret": String(describing: input.convert(input.caretRect(for: range.start), to: nil)),
      "endCaret": String(describing: input.convert(input.caretRect(for: range.end), to: nil)),
      "selectionRects": input.selectionRects(for: range).map {
        ["rect": String(describing: input.convert($0.rect, to: nil)), "rtl": $0.writingDirection.rawValue, "start": $0.containsStart, "end": $0.containsEnd]
      }
    ]
    for (key, direction) in [("left", UITextLayoutDirection.left), ("right", .right)] {
      if let position = input.position(within: range, farthestIn: direction) {
        result[key] = input.offset(from: input.beginningOfDocument, to: position)
      }
      if let second = input.position(from: input.beginningOfDocument, offset: 2),
        let next = input.position(from: second, in: direction, offset: 1)
      {
        result["move_\(key)"] = input.offset(from: input.beginningOfDocument, to: next)
        if let extended = input.characterRange(byExtending: second, in: direction) {
          result["extend_\(key)"] = [
            input.offset(from: input.beginningOfDocument, to: extended.start),
            input.offset(from: input.beginningOfDocument, to: extended.end)
          ]
        }
      }
    }
    var tokens: [String: Int] = [:]
    for offset in [0, 5, 13] {
      guard let position = input.position(from: input.beginningOfDocument, offset: offset) else { continue }
      for (name, raw) in [("left", UITextLayoutDirection.left.rawValue), ("right", UITextLayoutDirection.right.rawValue), ("forward", UITextStorageDirection.forward.rawValue), ("backward", UITextStorageDirection.backward.rawValue)] {
        let direction = UITextDirection(rawValue: raw)
        for (unit, granularity) in [("line", UITextGranularity.line), ("word", .word)] {
          if let boundary = input.tokenizer.position(from: position, toBoundary: granularity, inDirection: direction) {
            tokens["\(offset)_\(unit)_\(name)"] = input.offset(from: input.beginningOfDocument, to: boundary)
          }
        }
      }
    }
    result["tokens"] = tokens
    return result
  }


}

func box(_ start: Int, _ end: Int, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ rtl: Bool = false) -> [String: Any] {
  ["start": start, "end": end, "left": left, "top": top, "right": right, "bottom": bottom, "rtl": rtl]
}

final class HarnessCanvas: UIView {
  static let rtl = ProcessInfo.processInfo.arguments.contains("--rtl")
  static let reference = ProcessInfo.processInfo.arguments.contains("--reference")
  static let middle = ProcessInfo.processInfo.arguments.contains("--middle")
  static let atomic = ProcessInfo.processInfo.arguments.contains("--atomic")
  static let initialBase = middle ? 7 : 0
  static let initialExtent = middle ? 16 : (rtl ? 5 : 6)
  static let text = rtl
    ? "مرحبا بالعالم — Flutter 123\nالقراءة باللغة العربية"
    : "Native selection text\nSecond line in the book."
  private static let textStorage: NSTextStorage = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .rightToLeft
    paragraph.alignment = .right
    return NSTextStorage(string: text, attributes: [
      .font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.black,
      .paragraphStyle: paragraph
    ])
  }()
  static var attributedText: NSAttributedString { textStorage }
  private static let geometryView: UITextView = {
    let view = UITextView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 48, height: 240))
    view.isScrollEnabled = false
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.attributedText = attributedText
    view.layoutIfNeeded()
    return view
  }()
  private static let textContainer = NSTextContainer(size: CGSize(width: UIScreen.main.bounds.width - 48, height: 240))
  private static var textBounds: CGRect {
    CGRect(x: 24, y: 160, width: textContainer.size.width, height: textContainer.size.height)
  }
  private static let layoutManager: NSLayoutManager = {
    let manager = NSLayoutManager()
    textContainer.lineFragmentPadding = 0
    textStorage.addLayoutManager(manager)
    manager.addTextContainer(textContainer)
    manager.ensureLayout(for: textContainer)
    return manager
  }()
  static let boxes: [[String: Any]] = {
    var boxes: [[String: Any]] = []
    if atomic {
      (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: .byWords) { _, range, _, _ in
        let firstLine = range.location < 22
        let column = firstLine ? range.location : range.location - 22
        let y = firstLine ? 160.0 : 200.0
        boxes.append(box(range.location, NSMaxRange(range), 40 + Double(column) * 15, y, 40 + Double(column + range.length) * 15, y + 32))
      }
      return boxes
    }
    if rtl {
      let manager = layoutManager
      (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: .byComposedCharacterSequences) { value, range, _, _ in
        if value == "\n" { return }
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        guard let start = geometryView.position(from: geometryView.beginningOfDocument, offset: range.location),
          let end = geometryView.position(from: start, offset: range.length),
          let textRange = geometryView.textRange(from: start, to: end)
        else { return }
        // Glyph ink bounds may include fallback-font overhangs. UIKit's text
        // ranges supply the shaped cell advances used by selection controls.
        let rect = geometryView.selectionRects(for: textRange).filter { !$0.rect.isEmpty }
          .reduce(CGRect.null) { $0.union($1.rect) }
          .offsetBy(dx: 24, dy: 160).intersection(textBounds)
        guard !rect.isEmpty else { return }
        var levels = [UInt8](repeating: 0, count: glyphs.length)
        _ = levels.withUnsafeMutableBufferPointer {
          manager.getGlyphs(in: glyphs, glyphs: nil, properties: nil, characterIndexes: nil, bidiLevels: $0.baseAddress)
        }
        boxes.append(box(range.location, NSMaxRange(range), rect.minX, rect.minY, rect.maxX, rect.maxY, levels[0] & 1 == 1))
      }
      return boxes
    }
    var x = 40.0
    var y = 160.0
    (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: .byComposedCharacterSequences) { value, range, _, _ in
      if value == "\n" { x = 40; y += 40; return }
      boxes.append(box(range.location, NSMaxRange(range), x, y, x + 15, y + 32))
      x += 15
    }
    return boxes
  }()

  override func draw(_ rect: CGRect) {
    if Self.rtl {
      let context = UIGraphicsGetCurrentContext()
      context?.saveGState()
      context?.clip(to: Self.textBounds)
      Self.layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: Self.layoutManager.numberOfGlyphs), at: CGPoint(x: 24, y: 160))
      context?.restoreGState()
      return
    }
    let font = UIFont.monospacedSystemFont(ofSize: 25, weight: .regular)
    for box in Self.boxes {
      let range = NSRange(location: box["start"] as! Int, length: (box["end"] as! Int) - (box["start"] as! Int))
      ((Self.text as NSString).substring(with: range) as NSString).draw(at: CGPoint(x: box["left"] as! Double, y: box["top"] as! Double), withAttributes: [.font: font, .foregroundColor: UIColor.black])
    }
  }
}
