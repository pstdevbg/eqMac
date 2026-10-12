//
//  ParametricEqualizerState.swift
//  eqMac
//

import Foundation
import ReSwift
import SwiftyUserDefaults
import BetterCodable

struct ParametricEqualizerState: State {
  var selectedPresetId: String = "flat"
}

struct ParametricEqualizerStateDefault: DefaultCodableStrategy {
  static var defaultValue = ParametricEqualizerState()
}

enum ParametricEqualizerAction: Action {
  case selectPreset(String)
}

func ParametricEqualizerStateReducer(action: Action, state: ParametricEqualizerState?) -> ParametricEqualizerState {
  var state = state ?? ParametricEqualizerState()

  switch action as? ParametricEqualizerAction {
  case .selectPreset(let id)?:
    state.selectedPresetId = id
  case .none:
    break
  }

  return state
}
