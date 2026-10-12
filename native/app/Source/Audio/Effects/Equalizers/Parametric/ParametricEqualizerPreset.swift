//
//  ParametricEqualizerPreset.swift
//  eqMac
//

import Foundation
import SwiftyUserDefaults

enum ParametricEqualizerFilterType: String, Codable, CaseIterable {
  case peak = "PK"
  case lowShelf = "LSC"
  case highShelf = "HSC"
}

struct ParametricEqualizerBand: Codable, Equatable, DefaultsSerializable {
  var type: ParametricEqualizerFilterType
  var frequency: Double
  var gain: Double
  var q: Double
  var enabled: Bool

  static let frequencyRange = 10.0...24_000.0
  static let gainRange = -24.0...24.0
  static let qRange = 0.1...20.0
}

struct ParametricEqualizerPreset: Codable, DefaultsSerializable {
  let id: String
  let name: String
  let isDefault: Bool
  let preamp: Double
  let bands: [ParametricEqualizerBand]

  static let maxBands = 20
  static let preampRange = -30.0...24.0

  func hasSameSettings (as other: ParametricEqualizerPreset) -> Bool {
    return preamp == other.preamp && bands == other.bands
  }
}

// Parser for the Equalizer APO "ParametricEQ.txt" format that AutoEq publishes, e.g.:
//   Preamp: -6.1 dB
//   Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
//   Filter 2: ON PK Fc 8800 Hz Gain 5.1 dB Q 1.42
struct ParametricEQText {
  struct Parsed {
    let preamp: Double
    let bands: [ParametricEqualizerBand]
  }

  private static let preampRegex = try! NSRegularExpression(
    pattern: #"^\s*Preamp:\s*([-+]?[0-9]*\.?[0-9]+)\s*dB"#,
    options: [.caseInsensitive]
  )
  private static let filterRegex = try! NSRegularExpression(
    pattern: #"^\s*Filter\s*\d*\s*:\s*(ON|OFF)\s+([A-Z]+)\s+Fc\s+([0-9]*\.?[0-9]+)\s*Hz(?:\s+Gain\s+([-+]?[0-9]*\.?[0-9]+)\s*dB)?(?:\s+Q\s+([0-9]*\.?[0-9]+))?"#,
    options: [.caseInsensitive]
  )

  static func filterType (from code: String) -> ParametricEqualizerFilterType? {
    switch code.uppercased() {
    case "PK", "PEQ": return .peak
    case "LSC", "LS", "LSQ": return .lowShelf
    case "HSC", "HS", "HSQ": return .highShelf
    default: return nil
    }
  }

  static func parse (_ text: String) throws -> Parsed {
    var preamp = 0.0
    var bands: [ParametricEqualizerBand] = []

    for line in text.components(separatedBy: .newlines) {
      let range = NSRange(line.startIndex..., in: line)
      func group (_ match: NSTextCheckingResult, _ index: Int) -> String? {
        guard let r = Range(match.range(at: index), in: line) else { return nil }
        return String(line[r])
      }

      if let match = preampRegex.firstMatch(in: line, range: range) {
        preamp = Double(group(match, 1)!) ?? 0
        continue
      }

      guard let match = filterRegex.firstMatch(in: line, range: range) else { continue }
      let code = group(match, 2)!
      guard let type = filterType(from: code) else {
        throw "Unsupported filter type '\(code)'. Only peak (PK) and shelf (LSC/HSC) filters are supported."
      }
      bands.append(ParametricEqualizerBand(
        type: type,
        frequency: Double(group(match, 3)!) ?? 1_000,
        gain: Double(group(match, 4) ?? "0") ?? 0,
        q: Double(group(match, 5) ?? "") ?? 0.707,
        enabled: group(match, 1)!.uppercased() == "ON"
      ))
    }

    if bands.isEmpty {
      throw "No filters found. Expected lines like 'Filter 1: ON PK Fc 1000 Hz Gain -2.0 dB Q 1.41'."
    }
    if bands.count > ParametricEqualizerPreset.maxBands {
      throw "Too many filters (\(bands.count)). The Parametric Equalizer supports up to \(ParametricEqualizerPreset.maxBands)."
    }
    return Parsed(preamp: preamp, bands: bands)
  }
}
