//
//  ParametricEqualizer.swift
//  eqMac
//

import Foundation
import ReSwift
import EmitterKit
import AVFoundation

class ParametricEqualizer: Equalizer, StoreSubscriber {
  static let flatPreset = ParametricEqualizerPreset(id: "flat", name: "Flat", isDefault: true, preamp: 0, bands: [])

  static var userPresets: [ParametricEqualizerPreset] {
    get {
      return Storage[.parametricEqualizerPresets] ?? []
    }
    set (newPresets) {
      Storage[.parametricEqualizerPresets] = newPresets
      presetsChanged.emit(presets)
    }
  }

  static var presets: [ParametricEqualizerPreset] {
    var presets = userPresets
    if !presets.contains(where: { $0.id == "manual" }) {
      presets.append(ParametricEqualizerPreset(id: "manual", name: "Manual", isDefault: true, preamp: 0, bands: []))
    }
    presets.append(flatPreset)
    return presets
  }

  static func getPreset (id: String) -> ParametricEqualizerPreset? {
    return presets.first(where: { $0.id == id })
  }

  static func getPreset (name: String) -> ParametricEqualizerPreset? {
    return userPresets.first(where: { $0.name == name && $0.id != "manual" })
  }

  static func createPreset (name: String, preamp: Double, bands: [ParametricEqualizerBand]) -> ParametricEqualizerPreset {
    let preset = ParametricEqualizerPreset(id: UUID().uuidString, name: name, isDefault: false, preamp: preamp, bands: bands)
    userPresets.append(preset)
    return preset
  }

  static func updatePreset (id: String, name: String? = nil, preamp: Double, bands: [ParametricEqualizerBand]) {
    guard let existing = getPreset(id: id), id != flatPreset.id else { return }
    var presets = userPresets
    presets.removeAll(where: { $0.id == id })
    presets.append(ParametricEqualizerPreset(
      id: id,
      name: name ?? existing.name,
      isDefault: id == "manual",
      preamp: preamp,
      bands: bands
    ))
    userPresets = presets
  }

  static func deletePreset (_ preset: ParametricEqualizerPreset) {
    userPresets.removeAll(where: { $0.id == preset.id })
  }

  static var presetsChanged = Event<[ParametricEqualizerPreset]>()

  var selectedPreset: ParametricEqualizerPreset = ParametricEqualizer.flatPreset {
    didSet {
      apply()
    }
  }

  var state: ParametricEqualizerState {
    return Application.store.state.effects.equalizers.parametric
  }

  init () {
    Console.log("Creating Parametric Equalizer")
    super.init(numberOfBands: ParametricEqualizerPreset.maxBands)

    if let preset = ParametricEqualizer.getPreset(id: state.selectedPresetId) {
      ({ self.selectedPreset = preset })()
    } else {
      apply()
    }
    setupStateListener()
  }

  override func sampleRateDidSet () {
    apply()
  }

  // Bandwidth in octaves for a given Q, including the bilinear-transform frequency warping
  // that AVAudioUnitEQ applies (RBJ Audio EQ Cookbook). Measured against the RBJ biquad response
  // this matches peak and shelf filters to within 0.01 dB at 44.1/48/96 kHz.
  static func bandwidth (q: Double, frequency: Double, sampleRate: Double) -> Float {
    let w0 = 2 * Double.pi * frequency / sampleRate
    let octaves = 2 * asinh(1 / (2 * q)) / log(2) * sin(w0) / w0
    return Float(min(max(octaves, 0.05), 5.0))
  }

  private func apply () {
    globalGain = selectedPreset.preamp
    let nyquistLimit = sampleRate * 0.49

    for (index, band) in eq.bands.enumerated() {
      guard index < selectedPreset.bands.count, selectedPreset.bands[index].enabled else {
        band.bypass = true
        band.gain = 0
        continue
      }
      let settings = selectedPreset.bands[index]
      let frequency = min(settings.frequency, nyquistLimit)
      switch settings.type {
      case .peak: band.filterType = .parametric
      case .lowShelf: band.filterType = .resonantLowShelf
      case .highShelf: band.filterType = .resonantHighShelf
      }
      band.frequency = Float(frequency)
      band.bandwidth = ParametricEqualizer.bandwidth(q: settings.q, frequency: frequency, sampleRate: sampleRate)
      band.gain = Float(settings.gain)
      band.bypass = false
    }
  }

  func setupStateListener () {
    Application.store.subscribe(self) { subscription in
      subscription.select { state in state.effects.equalizers.parametric }
    }
  }

  func newState (state: ParametricEqualizerState) {
    if let preset = ParametricEqualizer.getPreset(id: state.selectedPresetId) {
      if selectedPreset.id != preset.id || !selectedPreset.hasSameSettings(as: preset) {
        selectedPreset = preset
      }
    }
  }

  typealias StoreSubscriberStateType = ParametricEqualizerState

  deinit {
    Application.store.unsubscribe(self)
  }
}
