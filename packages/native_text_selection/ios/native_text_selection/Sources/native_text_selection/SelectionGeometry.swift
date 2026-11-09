import UIKit

struct SelectionBox {
  let start: Int
  let end: Int
  let rect: CGRect
  let rtl: Bool

  var leadingX: CGFloat { rtl ? rect.maxX : rect.minX }
  var trailingX: CGFloat { rtl ? rect.minX : rect.maxX }

  init?(_ value: [String: Any], length: Int) {
    guard let start = value["start"] as? Int,
      let end = value["end"] as? Int,
      let left = value["left"] as? Double,
      let top = value["top"] as? Double,
      let right = value["right"] as? Double,
      let bottom = value["bottom"] as? Double,
      start >= 0, start < end, end <= length,
      left.isFinite, top.isFinite, right.isFinite, bottom.isFinite,
      right >= left, bottom > top
    else { return nil }
    self.start = start
    self.end = end
    rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    rtl = value["rtl"] as? Bool ?? false
  }
}

/// Native geometry contains only the mounted text surface, never a whole book.
struct SelectionGeometry {
  let text: NSString
  let boxes: [SelectionBox]
  let boundaries: [Int]
  private let rows: [SelectionRow]

  init(text: String, boxes: [[String: Any]]) {
    self.text = text as NSString
    self.boxes = boxes.compactMap { SelectionBox($0, length: (text as NSString).length) }
      .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    var boundaries = [0]
    (text as NSString).enumerateSubstrings(
      in: NSRange(location: 0, length: (text as NSString).length),
      options: .byComposedCharacterSequences
    ) { _, range, _, _ in boundaries.append(NSMaxRange(range)) }
    self.boundaries = boundaries
    var rows: [SelectionRow] = []
    for box in self.boxes.sorted(by: { $0.rect.midY < $1.rect.midY }) {
      if let last = rows.last,
        abs(last.rect.midY - box.rect.midY) < min(last.rect.height, box.rect.height) * 0.4
      {
        rows[rows.count - 1].append(box)
      } else {
        rows.append(SelectionRow(boxes: [box], rect: box.rect))
      }
    }
    self.rows = rows
  }

  var length: Int { text.length }

  func snapped(_ raw: Int, forward: Bool = false) -> Int {
    let offset = min(max(raw, 0), length)
    let index = lowerBound(boundaries, offset)
    if index < boundaries.count, boundaries[index] == offset { return offset }
    if forward, index < boundaries.count { return boundaries[index] }
    return boundaries[max(0, index - 1)]
  }

  func previousBoundary(_ raw: Int) -> Int {
    let offset = snapped(raw)
    return boundaries[max(0, lowerBound(boundaries, offset) - 1)]
  }

  func nextBoundary(_ raw: Int) -> Int {
    let offset = snapped(raw, forward: true)
    return boundaries[min(boundaries.count - 1, lowerBound(boundaries, offset) + 1)]
  }

  func box(at offset: Int, preferPrevious: Bool = false) -> SelectionBox? {
    guard !boxes.isEmpty else { return nil }
    var low = 0
    var high = boxes.count
    while low < high {
      let mid = low + (high - low) / 2
      if boxes[mid].end < offset || (!preferPrevious && boxes[mid].end == offset) {
        low = mid + 1
      } else { high = mid }
    }
    return boxes[min(low, boxes.count - 1)]
  }

  func caret(at raw: Int, preferPrevious: Bool = false) -> CGRect {
    let offset = snapped(raw, forward: !preferPrevious)
    guard let box = box(at: offset, preferPrevious: preferPrevious) else { return .zero }
    let x = offset >= box.end ? box.trailingX : box.leadingX
    return CGRect(x: x, y: box.rect.minY, width: 1, height: box.rect.height)
  }

  func nearest(to point: CGPoint, within range: Range<Int>? = nil) -> Int? {
    guard let row = nearestRow(to: point) else { return nil }
    var nearestOffset: Int?
    var distance = CGFloat.infinity
    for box in row.boxes {
      for (offset, x) in [(box.start, box.leadingX), (box.end, box.trailingX)] {
        if let range, offset < range.lowerBound || offset > range.upperBound { continue }
        let value = abs(point.x - x)
        if value < distance {
          distance = value
          nearestOffset = offset
        }
      }
    }
    if let nearestOffset { return snapped(nearestOffset) }
    if let range {
      let unrestricted = nearest(to: point) ?? range.lowerBound
      return snapped(min(max(unrestricted, range.lowerBound), range.upperBound))
    }
    return nil
  }

  func character(at point: CGPoint) -> SelectionBox? {
    nearestRow(to: point)?.boxes.min {
      max($0.rect.minX - point.x, point.x - $0.rect.maxX, 0)
        < max($1.rect.minX - point.x, point.x - $1.rect.maxX, 0)
    }
  }

  private func nearestRow(to point: CGPoint) -> SelectionRow? {
    guard !rows.isEmpty else { return nil }
    var low = 0
    var high = rows.count
    while low < high {
      let mid = low + (high - low) / 2
      if rows[mid].rect.midY < point.y { low = mid + 1 } else { high = mid }
    }
    return [max(0, low - 1), min(rows.count - 1, low)].map { rows[$0] }.min {
      verticalDistance(point.y, $0.rect) < verticalDistance(point.y, $1.rect)
    }
  }

  func line(containing offset: Int) -> Range<Int>? {
    guard let box = box(at: offset),
      let row = rows.first(where: { $0.boxes.contains(where: { $0.start == box.start }) })
    else { return nil }
    let ordered = row.boxes.sorted { $0.start < $1.start }
    guard let index = ordered.firstIndex(where: { $0.start == box.start }) else { return nil }
    var first = index
    var last = index
    while first > 0, isContiguous(ordered[first - 1], ordered[first]) { first -= 1 }
    while last + 1 < ordered.count, isContiguous(ordered[last], ordered[last + 1]) { last += 1 }
    return ordered[first].start..<ordered[last].end
  }

  private func isContiguous(_ first: SelectionBox, _ second: SelectionBox) -> Bool {
    guard first.end < second.start else { return true }
    let gap = text.substring(with: NSRange(location: first.end, length: second.start - first.end))
    return gap.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) == nil
  }

  func selectionRects(start: Int, end: Int) -> [NativeSelectionRect] {
    guard start < end else { return [] }
    let selected = boxes.filter { $0.end > start && $0.start < end }
    var groups: [(CGRect, Bool, Int, Int)] = []
    for box in selected {
      if let previous = groups.last,
        previous.1 == box.rtl,
        abs(previous.0.midY - box.rect.midY) < min(previous.0.height, box.rect.height) * 0.3,
        max(previous.0.minX, box.rect.minX) - min(previous.0.maxX, box.rect.maxX) < 1.5
      {
        groups[groups.count - 1] = (
          previous.0.union(box.rect), previous.1, min(previous.2, box.start), max(previous.3, box.end)
        )
      } else { groups.append((box.rect, box.rtl, box.start, box.end)) }
    }
    return groups.enumerated().map { index, group in
      NativeSelectionRect(
        rect: group.0,
        rtl: group.1,
        containsStart: index == 0,
        containsEnd: index == groups.count - 1
      )
    }
  }
}

private struct SelectionRow {
  var boxes: [SelectionBox]
  var rect: CGRect

  mutating func append(_ box: SelectionBox) {
    boxes.append(box)
    rect = rect.union(box.rect)
  }
}

private func lowerBound(_ values: [Int], _ target: Int) -> Int {
  var low = 0
  var high = values.count
  while low < high {
    let mid = low + (high - low) / 2
    if values[mid] < target { low = mid + 1 } else { high = mid }
  }
  return low
}

private func verticalDistance(_ y: CGFloat, _ rect: CGRect) -> CGFloat {
  max(rect.minY - y, y - rect.maxY, 0)
}

final class NativeTextPosition: UITextPosition {
  let offset: Int
  init(_ offset: Int) { self.offset = offset }

  override func isEqual(_ object: Any?) -> Bool {
    (object as? NativeTextPosition)?.offset == offset
  }

  override var hash: Int { offset.hashValue }
}

final class NativeTextRange: UITextRange {
  let base: Int
  let extent: Int
  var lower: Int { min(base, extent) }
  var upper: Int { max(base, extent) }
  override var start: UITextPosition { NativeTextPosition(lower) }
  override var end: UITextPosition { NativeTextPosition(upper) }
  override var isEmpty: Bool { base == extent }

  init(base: Int, extent: Int) {
    self.base = base
    self.extent = extent
  }
}

final class NativeSelectionRect: UITextSelectionRect {
  private let selectionRect: CGRect
  private let rtl: Bool
  private let starts: Bool
  private let ends: Bool
  override var rect: CGRect { selectionRect }
  override var writingDirection: NSWritingDirection { rtl ? .rightToLeft : .leftToRight }
  override var containsStart: Bool { starts }
  override var containsEnd: Bool { ends }
  override var isVertical: Bool { false }

  init(rect: CGRect, rtl: Bool, containsStart: Bool, containsEnd: Bool) {
    selectionRect = rect
    self.rtl = rtl
    starts = containsStart
    ends = containsEnd
  }
}
