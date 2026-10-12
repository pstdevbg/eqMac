import { Injectable } from '@angular/core'
import { EqualizersService } from '../equalizers.service'
import { EqualizerPreset } from '../presets/equalizer-presets.component'

export type ParametricEqualizerFilterType = 'PK' | 'LSC' | 'HSC'

export interface ParametricEqualizerBand {
  type: ParametricEqualizerFilterType
  frequency: number
  gain: number
  q: number
  enabled: boolean
}

export interface ParametricEqualizerPreset extends EqualizerPreset {
  preamp: number
  bands: ParametricEqualizerBand[]
}

export interface AutoEqResult {
  path: string
  name: string
  source: string
  label: string
}

export interface AutoEqModel {
  brand?: string
  model: string
  entries: AutoEqResult[]
}

export const PARAMETRIC_EQUALIZER_MAX_BANDS = 20
export const PARAMETRIC_EQUALIZER_LIMITS = {
  frequency: { min: 10, max: 24000 },
  gain: { min: -24, max: 24 },
  q: { min: 0.1, max: 20 },
  preamp: { min: -30, max: 24 }
}

@Injectable({
  providedIn: 'root'
})
export class ParametricEqualizerService extends EqualizersService {
  route = `${this.route}/parametric`

  getPresets (): Promise<ParametricEqualizerPreset[]> {
    return this.request({ method: 'GET', endpoint: '/presets' })
  }

  getSelectedPreset (): Promise<ParametricEqualizerPreset> {
    return this.request({ method: 'GET', endpoint: '/presets/selected' })
  }

  createPreset (preset: Omit<ParametricEqualizerPreset, 'id'>, select = false): Promise<ParametricEqualizerPreset> {
    return this.request({ method: 'POST', endpoint: '/presets', data: { ...preset, select } as any })
  }

  updatePreset (preset: ParametricEqualizerPreset, opts?: { select?: boolean }) {
    return this.request({
      method: 'POST',
      endpoint: '/presets',
      data: {
        id: preset.id,
        preamp: preset.preamp,
        bands: preset.bands as any,
        select: !!opts?.select
      }
    })
  }

  selectPreset (preset: ParametricEqualizerPreset) {
    return this.request({ method: 'POST', endpoint: '/presets/select', data: { id: preset.id } })
  }

  deletePreset (preset: ParametricEqualizerPreset) {
    return this.request({ method: 'DELETE', endpoint: '/presets', data: { id: preset.id } })
  }

  importPresets (): Promise<string> {
    return this.request({ method: 'GET', endpoint: '/presets/import' })
  }

  exportPresets (): Promise<string> {
    return this.request({ method: 'GET', endpoint: '/presets/export' })
  }

  async getAutoEqBrands (): Promise<string[]> {
    const { brands } = await this.request({ method: 'GET', endpoint: '/autoeq/brands' })
    return brands
  }

  getAutoEqModels (brand: string): Promise<AutoEqModel[]> {
    return this.request({ method: 'GET', endpoint: '/autoeq/models', data: { brand } })
  }

  searchAutoEq (query: string): Promise<AutoEqModel[]> {
    return this.request({ method: 'GET', endpoint: '/autoeq/search', data: { query } })
  }

  loadAutoEqResult (result: AutoEqResult): Promise<ParametricEqualizerPreset> {
    return this.request({
      method: 'POST',
      endpoint: '/autoeq/load',
      data: { path: result.path, name: result.name, label: result.label }
    })
  }

  refreshAutoEq (): Promise<string> {
    return this.request({ method: 'POST', endpoint: '/autoeq/refresh' })
  }

  onPresetsChanged (callback: ParametricEqualizerPresetsChangedEventCallback) {
    this.on('/presets', callback)
  }

  offPresetsChanged (callback: ParametricEqualizerPresetsChangedEventCallback) {
    this.off('/presets', callback)
  }
}

export type ParametricEqualizerPresetsChangedEventCallback = (presets: ParametricEqualizerPreset[]) => void
