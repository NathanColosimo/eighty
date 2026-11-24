/// Whether dotted version `candidate` (like "0.1.10") is newer than `current`.
/// Missing parts count as 0; anything unparsable is never newer.
public func isNewer(_ candidate: String, than current: String) -> Bool {
  func parts(_ version: String) -> [Int]? {
    let numbers = version.split(separator: ".").map { Int($0) }
    return numbers.contains(nil) || numbers.isEmpty ? nil : numbers.compactMap { $0 }
  }
  guard let a = parts(candidate), let b = parts(current) else { return false }
  for i in 0..<max(a.count, b.count) {
    let x = i < a.count ? a[i] : 0
    let y = i < b.count ? b[i] : 0
    if x != y { return x > y }
  }
  return false
}
