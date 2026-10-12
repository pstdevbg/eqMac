//
//  AutoEq.swift
//  eqMac
//
//  Client for the AutoEq headphone equalization database (https://github.com/jaakkopasanen/AutoEq).
//  The results index and manufacturer list are downloaded from GitHub and cached on disk.
//

import Foundation

struct AutoEqEntry: Codable {
  let name: String
  let brand: String
  let model: String
  let source: String
  let rig: String?
  let path: String

  var label: String {
    return rig != nil ? "\(source) (\(rig!))" : source
  }
}

class AutoEq {
  static let baseURL = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master")!
  static let indexURL = baseURL.appendingPathComponent("results/INDEX.md")
  static let manufacturersURL = baseURL.appendingPathComponent("dbtools/manufacturers.tsv")
  static let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60

  // Measurement sources in order of preference, following AutoEq's own recommendation
  static let preferredSources = [
    "oratory1990", "crinacle", "Rtings", "Innerfidelity", "Kuulokenurkka", "Super Review", "Headphone.com Legacy"
  ]

  private static var entries: [AutoEqEntry]?
  private static let queue = DispatchQueue(label: "eqMac.AutoEq")

  static var cacheDirectory: URL {
    let dir = Application.supportPath.appendingPathComponent("AutoEq", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - Catalog

  static func getEntries (forceRefresh: Bool = false, _ completion: @escaping (Result<[AutoEqEntry], Error>) -> Void) {
    queue.async {
      if !forceRefresh, let entries = entries {
        return completion(.success(entries))
      }
      let group = DispatchGroup()
      var index: Result<String, Error>!
      var manufacturers: Result<String, Error>!
      group.enter()
      cachedText(url: indexURL, file: "INDEX.md", forceRefresh: forceRefresh) { index = $0; group.leave() }
      group.enter()
      cachedText(url: manufacturersURL, file: "manufacturers.tsv", forceRefresh: forceRefresh) { manufacturers = $0; group.leave() }
      group.wait()

      do {
        let parsed = parseIndex(try index.get(), manufacturers: parseManufacturers(try manufacturers.get()))
        if parsed.isEmpty {
          throw "The AutoEq index could not be read."
        }
        entries = parsed
        completion(.success(parsed))
      } catch {
        completion(.failure(error))
      }
    }
  }

  static func brands (_ entries: [AutoEqEntry]) -> [String] {
    return Array(Set(entries.map { $0.brand })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  static func models (_ entries: [AutoEqEntry], brand: String) -> [(model: String, entries: [AutoEqEntry])] {
    let grouped = Dictionary(grouping: entries.filter { $0.brand == brand }, by: { $0.model })
    return grouped
      .map { (model: $0.key, entries: $0.value.sorted(by: sourceOrder)) }
      .sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
  }

  // Finds models whose "brand model" contains every word of the query. Words also match with spaces and
  // punctuation ignored, so "hd650" finds "HD 650" and "athm50x" finds "ATH-M50x".
  static func search (_ entries: [AutoEqEntry], query: String, limit: Int = 100) -> [(brand: String, model: String, entries: [AutoEqEntry])] {
    func compact (_ s: String) -> String {
      return String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
    let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !words.isEmpty else { return [] }
    let fullQuery = words.joined(separator: " ")

    let groups = Dictionary(grouping: entries, by: { "\($0.brand)\u{0}\($0.model)" })
    var matches: [(rank: Int, name: String, brand: String, model: String, entries: [AutoEqEntry])] = []
    for group in groups.values {
      let first = group[0]
      let name = "\(first.brand) \(first.model)"
      let text = name.lowercased()
      let compactText = compact(name)
      let matchesAll = words.allSatisfy { word in
        let compactWord = compact(word)
        return text.contains(word) || (!compactWord.isEmpty && compactText.contains(compactWord))
      }
      guard matchesAll else { continue }
      let model = first.model.lowercased()
      let rank = text == fullQuery || model == fullQuery ? 0
        : text.hasPrefix(fullQuery) || model.hasPrefix(fullQuery) ? 1
        : 2
      matches.append((rank, name, first.brand, first.model, group.sorted(by: sourceOrder)))
    }
    return matches
      .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      .prefix(limit)
      .map { (brand: $0.brand, model: $0.model, entries: $0.entries) }
  }

  private static func sourceOrder (_ a: AutoEqEntry, _ b: AutoEqEntry) -> Bool {
    let rank = { (source: String) in preferredSources.firstIndex(of: source) ?? preferredSources.count }
    if rank(a.source) != rank(b.source) { return rank(a.source) < rank(b.source) }
    return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
  }

  // MARK: - Presets

  static func fetchParametricEQ (path: String, _ completion: @escaping (Result<ParametricEQText.Parsed, Error>) -> Void) {
    let name = (path as NSString).lastPathComponent
    let url = baseURL
      .appendingPathComponent("results")
      .appendingPathComponent(path)
      .appendingPathComponent("\(name) ParametricEQ.txt")
    download(url) { result in
      completion(Result { try ParametricEQText.parse(try result.get()) })
    }
  }

  // MARK: - Parsing

  // Maps every known manufacturer spelling (lowercased) to its canonical name
  static func parseManufacturers (_ tsv: String) -> [String: String] {
    var names: [String: String] = [:]
    for line in tsv.components(separatedBy: .newlines) {
      let aliases = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      guard let canonical = aliases.first else { continue }
      for alias in aliases {
        names[alias.lowercased()] = canonical
      }
    }
    return names
  }

  // Same approach as AutoEq's ManufacturerIndex.find: longest leading run of words that is a known manufacturer
  static func splitBrand (_ name: String, manufacturers: [String: String]) -> (brand: String, model: String) {
    let words = name.components(separatedBy: " ")
    for count in stride(from: words.count, to: 0, by: -1) {
      let candidate = words[0..<count].joined(separator: " ").lowercased()
      if let brand = manufacturers[candidate] {
        let model = words[count...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (brand, model.isEmpty ? name : model)
      }
    }
    let brand = words.first ?? name
    let model = words.dropFirst().joined(separator: " ")
    return (brand, model.isEmpty ? name : model)
  }

  private static let indexLineRegex = try! NSRegularExpression(pattern: #"^- \[(.+)\]\(\./(.+)\) by (.+?)(?: on (.+))?$"#)

  // INDEX.md lines look like: - [Sennheiser HD 650](./crinacle/GRAS%2043AG-7%20over-ear/Sennheiser%20HD%20650) by crinacle on GRAS 43AG-7
  static func parseIndex (_ markdown: String, manufacturers: [String: String]) -> [AutoEqEntry] {
    var entries: [AutoEqEntry] = []
    for line in markdown.components(separatedBy: .newlines) where line.hasPrefix("- [") {
      let range = NSRange(line.startIndex..., in: line)
      guard let match = indexLineRegex.firstMatch(in: line, range: range) else { continue }
      func group (_ index: Int) -> String? {
        guard let r = Range(match.range(at: index), in: line) else { return nil }
        return String(line[r])
      }
      let name = group(1)!
      guard let path = group(2)!.removingPercentEncoding else { continue }
      let (brand, model) = splitBrand(name, manufacturers: manufacturers)
      entries.append(AutoEqEntry(name: name, brand: brand, model: model, source: group(3)!, rig: group(4), path: path))
    }
    return entries
  }

  // MARK: - Networking

  private static func cachedText (url: URL, file: String, forceRefresh: Bool, _ completion: @escaping (Result<String, Error>) -> Void) {
    let cacheFile = cacheDirectory.appendingPathComponent(file)
    let cached = try? String(contentsOf: cacheFile, encoding: .utf8)
    let modified = (try? FileManager.default.attributesOfItem(atPath: cacheFile.path))?[.modificationDate] as? Date
    if !forceRefresh, let cached = cached, let modified = modified, Date().timeIntervalSince(modified) < cacheMaxAge {
      return completion(.success(cached))
    }
    download(url) { result in
      switch result {
      case .success(let text):
        try? text.write(to: cacheFile, atomically: true, encoding: .utf8)
        completion(.success(text))
      case .failure(let error):
        // Offline or GitHub unavailable: fall back to a stale cache if there is one
        if let cached = cached {
          Console.log("AutoEq: using cached \(file) after download failed: \(error.localizedDescription)")
          completion(.success(cached))
        } else {
          completion(.failure(error))
        }
      }
    }
  }

  private static func download (_ url: URL, _ completion: @escaping (Result<String, Error>) -> Void) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.httpMethod = "GET"
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        return completion(.failure("Could not reach AutoEq: \(error.localizedDescription)"))
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200, let data = data, let text = String(data: data, encoding: .utf8) else {
        return completion(.failure(status == 404 ? "This AutoEq result has no parametric EQ file." : "AutoEq request failed (HTTP \(status))."))
      }
      completion(.success(text))
    }.resume()
  }
}
