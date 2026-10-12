//
//  ParametricEqualizerDataBus.swift
//  eqMac
//

import Foundation
import SwiftyJSON
import EmitterKit

class ParametricEqualizerDataBus: DataBus {
  var state: ParametricEqualizerState {
    return Application.store.state.effects.equalizers.parametric
  }
  var presetsChangedListener: EventListener<[ParametricEqualizerPreset]>?

  required init (route: String, bridge: Bridge) {
    super.init(route: route, bridge: bridge)

    self.on(.GET, "/presets") { _, _ in
      return JSON(ParametricEqualizer.presets.map { $0.dictionary })
    }

    self.on(.GET, "/presets/selected") { _, _ in
      let preset = ParametricEqualizer.getPreset(id: self.state.selectedPresetId) ?? ParametricEqualizer.flatPreset
      return JSON(preset.dictionary)
    }

    self.on(.POST, "/presets") { data, _ in
      let preamp = try self.getPreamp(data)
      let bands = try self.getBands(data)
      let select = data["select"] as? Bool == true

      if let id = data["id"] as? String {
        // Update
        if id == ParametricEqualizer.flatPreset.id {
          throw "Default Presets aren't updatable."
        }
        guard ParametricEqualizer.getPreset(id: id) != nil else {
          throw "Could not find Preset with this ID"
        }
        ParametricEqualizer.updatePreset(id: id, preamp: preamp, bands: bands)
        if select || id == self.state.selectedPresetId {
          Application.dispatchAction(ParametricEqualizerAction.selectPreset(id))
        }
        return "Parametric Equalizer Preset has been updated"
      } else {
        // Create
        guard let name = data["name"] as? String, !name.isEmpty else {
          throw "Invalid 'name' parameter, must be a String"
        }
        let preset = ParametricEqualizer.createPreset(name: name, preamp: preamp, bands: bands)
        if select {
          Application.dispatchAction(ParametricEqualizerAction.selectPreset(preset.id))
        }
        return JSON(preset.dictionary)
      }
    }

    self.on(.POST, "/presets/select") { data, _ in
      let preset = try self.getPreset(data)
      Application.dispatchAction(ParametricEqualizerAction.selectPreset(preset.id))
      return "Parametric Equalizer Preset has been set."
    }

    self.on(.DELETE, "/presets") { data, _ in
      let preset = try self.getPreset(data)
      if preset.isDefault {
        throw "Default Presets aren't removable."
      }
      ParametricEqualizer.deletePreset(preset)
      Application.dispatchAction(ParametricEqualizerAction.selectPreset(ParametricEqualizer.flatPreset.id))
      return "Parametric Equalizer Preset has been deleted."
    }

    // Accepts either an exported eqMac JSON file or an Equalizer APO / AutoEq "ParametricEQ.txt" file
    self.on(.GET, "/presets/import") { _, res in
      File.select { file in
        guard let file = file else {
          return res.error("No file selected")
        }
        guard let text = try? String(contentsOf: file) else {
          return res.error("File is not readable format.")
        }
        if file.pathExtension.lowercased() == "json" {
          var imported = 0
          for preset in JSON(parseJSON: text).arrayValue {
            guard let name = preset["name"].string,
                  let bands = try? self.getBands(preset.dictionaryObject),
                  let preamp = try? self.getPreamp(preset.dictionaryObject) else { continue }
            if preset["id"].string == "manual" {
              ParametricEqualizer.updatePreset(id: "manual", preamp: preamp, bands: bands)
            } else {
              _ = ParametricEqualizer.createPreset(name: name, preamp: preamp, bands: bands)
            }
            imported += 1
          }
          res.send(JSON("Imported \(imported) Presets"))
        } else {
          do {
            let parsed = try ParametricEQText.parse(text)
            let name = file.deletingPathExtension().lastPathComponent
              .replacingOccurrences(of: " ParametricEQ", with: "")
            let preset = self.saveImported(name: name, parsed: parsed)
            Application.dispatchAction(ParametricEqualizerAction.selectPreset(preset.id))
            res.send(JSON("Imported \"\(preset.name)\" with \(parsed.bands.count) filters"))
          } catch {
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    self.on(.GET, "/presets/export") { _, res in
      File.save(extensions: ["json"]) { file in
        guard let file = file else {
          return res.error("Cancelled")
        }
        let presets = JSON(ParametricEqualizer.userPresets.map { $0.dictionary })
        do {
          try presets.rawString()!.write(to: file, atomically: true, encoding: .utf8)
          res.send(JSON("Exported \(presets.count) Presets"))
        } catch {
          res.error("Something went wrong")
        }
      }
      return nil
    }

    // MARK: - AutoEq

    self.on(.GET, "/autoeq/brands") { _, res in
      AutoEq.getEntries { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let entries):
            res.send(JSON([ "brands": AutoEq.brands(entries), "count": entries.count ]))
          case .failure(let error):
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    self.on(.GET, "/autoeq/models") { data, res in
      guard let brand = data["brand"] as? String else {
        throw "Please provide a 'brand' parameter"
      }
      AutoEq.getEntries { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let entries):
            let models = AutoEq.models(entries, brand: brand).map { group -> [String: Any] in
              return [
                "model": group.model,
                "entries": group.entries.map { [ "path": $0.path, "name": $0.name, "source": $0.source, "label": $0.label ] }
              ]
            }
            res.send(JSON(models))
          case .failure(let error):
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    self.on(.GET, "/autoeq/search") { data, res in
      let query = data["query"] as? String ?? ""
      AutoEq.getEntries { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let entries):
            let models = AutoEq.search(entries, query: query).map { group -> [String: Any] in
              return [
                "brand": group.brand,
                "model": group.model,
                "entries": group.entries.map { [ "path": $0.path, "name": $0.name, "source": $0.source, "label": $0.label ] }
              ]
            }
            res.send(JSON(models))
          case .failure(let error):
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    self.on(.POST, "/autoeq/load") { data, res in
      guard let path = data["path"] as? String, let name = data["name"] as? String else {
        throw "Please provide 'path' and 'name' parameters"
      }
      let source = data["label"] as? String
      AutoEq.fetchParametricEQ(path: path) { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let parsed):
            let presetName = source != nil ? "\(name) · \(source!)" : name
            let preset = self.saveImported(name: presetName, parsed: parsed)
            Application.dispatchAction(ParametricEqualizerAction.selectPreset(preset.id))
            res.send(JSON(preset.dictionary))
          case .failure(let error):
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    self.on(.POST, "/autoeq/refresh") { _, res in
      AutoEq.getEntries(forceRefresh: true) { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let entries):
            res.send(JSON("AutoEq database updated: \(entries.count) results"))
          case .failure(let error):
            res.error(error.localizedDescription)
          }
        }
      }
      return nil
    }

    presetsChangedListener = ParametricEqualizer.presetsChanged.on { presets in
      self.send(to: "/presets", data: JSON(presets.map { $0.dictionary }))
    }
  }

  // Re-importing the same headphone overwrites the existing preset instead of duplicating it
  private func saveImported (name: String, parsed: ParametricEQText.Parsed) -> ParametricEqualizerPreset {
    if let existing = ParametricEqualizer.getPreset(name: name) {
      ParametricEqualizer.updatePreset(id: existing.id, preamp: parsed.preamp, bands: parsed.bands)
      return ParametricEqualizer.getPreset(id: existing.id)!
    }
    return ParametricEqualizer.createPreset(name: name, preamp: parsed.preamp, bands: parsed.bands)
  }

  private func getPreset (_ data: JSON?) throws -> ParametricEqualizerPreset {
    guard let id = data["id"] as? String else {
      throw "Please provide a preset ID"
    }
    guard let preset = ParametricEqualizer.getPreset(id: id) else {
      throw "Could not find Preset with this ID"
    }
    return preset
  }

  private func getPreamp (_ data: [String: Any]?) throws -> Double {
    guard let preamp = data?["preamp"] as? Double, ParametricEqualizerPreset.preampRange.contains(preamp) else {
      throw "Invalid 'preamp' parameter, must be a number between \(ParametricEqualizerPreset.preampRange.lowerBound) and \(ParametricEqualizerPreset.preampRange.upperBound)"
    }
    return preamp
  }

  private func getPreamp (_ data: JSON?) throws -> Double {
    return try getPreamp(data?.dictionaryObject)
  }

  private func getBands (_ data: JSON?) throws -> [ParametricEqualizerBand] {
    return try getBands(data?.dictionaryObject)
  }

  private func getBands (_ data: [String: Any]?) throws -> [ParametricEqualizerBand] {
    guard let rawBands = data?["bands"] as? [[String: Any]] else {
      throw "Invalid 'bands' parameter, must be an Array of bands"
    }
    if rawBands.count > ParametricEqualizerPreset.maxBands {
      throw "Too many bands, the maximum is \(ParametricEqualizerPreset.maxBands)"
    }
    return try rawBands.enumerated().map { index, raw in
      guard let typeCode = raw["type"] as? String, let type = ParametricEqualizerFilterType(rawValue: typeCode) else {
        throw "Band \(index + 1): invalid 'type', must be one of \(ParametricEqualizerFilterType.allCases.map { $0.rawValue })"
      }
      guard let frequency = raw["frequency"] as? Double, ParametricEqualizerBand.frequencyRange.contains(frequency) else {
        throw "Band \(index + 1): 'frequency' must be between 10 and 24000 Hz"
      }
      guard let gain = raw["gain"] as? Double, ParametricEqualizerBand.gainRange.contains(gain) else {
        throw "Band \(index + 1): 'gain' must be between -24 and 24 dB"
      }
      guard let q = raw["q"] as? Double, ParametricEqualizerBand.qRange.contains(q) else {
        throw "Band \(index + 1): 'q' must be between 0.1 and 20"
      }
      return ParametricEqualizerBand(type: type, frequency: frequency, gain: gain, q: q, enabled: raw["enabled"] as? Bool ?? true)
    }
  }
}
