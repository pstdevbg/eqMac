import {
  Component,
  OnInit,
  Input,
  EventEmitter,
  Output,
  ChangeDetectorRef,
  OnDestroy,
  HostBinding
} from '@angular/core'
import { MatDialog } from '@angular/material/dialog'
import { ColorsService } from '@eqmac/components'
import { EqualizerComponent } from '../equalizer.component'
import { Options } from 'src/app/components/options/options.component'
import { ApplicationService } from '../../../../services/app.service'
import { ToastService } from '../../../../services/toast.service'
import {
  ParametricEqualizerService,
  ParametricEqualizerPreset,
  ParametricEqualizerFilterType,
  ParametricEqualizerPresetsChangedEventCallback,
  PARAMETRIC_EQUALIZER_MAX_BANDS,
  PARAMETRIC_EQUALIZER_LIMITS
} from './parametric-equalizer.service'
import { AutoEqDialogComponent } from './autoeq-dialog/autoeq-dialog.component'
import { magnitudeResponse } from './parametric-equalizer.response'

type BandField = 'frequency' | 'gain' | 'q'

const FILTER_TYPES: Array<{ type: ParametricEqualizerFilterType, label: string, name: string }> = [
  { type: 'PK', label: 'PK', name: 'Peak' },
  { type: 'LSC', label: 'LS', name: 'Low shelf' },
  { type: 'HSC', label: 'HS', name: 'High shelf' }
]

@Component({
  selector: 'eqm-parametric-equalizer',
  templateUrl: './parametric-equalizer.component.html',
  styleUrls: [ './parametric-equalizer.component.scss' ]
})
export class ParametricEqualizerComponent extends EqualizerComponent implements OnInit, OnDestroy {
  @Input() enabled = true

  static readonly graphHeight = 90
  static readonly rowHeight = 22
  static readonly maxVisibleRows = 10
  readonly maxBands = PARAMETRIC_EQUALIZER_MAX_BANDS
  readonly limits = PARAMETRIC_EQUALIZER_LIMITS

  @HostBinding('style.height.px') get height () {
    const rows = Math.min(Math.max(this.selectedPreset?.bands.length ?? 0, 1), ParametricEqualizerComponent.maxVisibleRows)
    // graph + preamp row + table header + rows + add button + spacing
    return ParametricEqualizerComponent.graphHeight + 24 + 14 + rows * ParametricEqualizerComponent.rowHeight + 22 + 40
  }

  settings: Options = [ [
    {
      type: 'button',
      label: 'Import Presets',
      tooltip: 'eqMac JSON export or an AutoEq / Equalizer APO ParametricEQ.txt file',
      action: async () => {
        const log = await this.service.importPresets()
        this.settingsDialog?.close()
        this.toast.show({ type: 'success', message: log })
        await this.syncPresets()
      }
    }, {
      type: 'button',
      label: 'Export Presets',
      action: async () => {
        const log = await this.service.exportPresets()
        this.toast.show({ type: 'success', message: log })
      }
    }
  ], [
    {
      type: 'button',
      label: 'Update AutoEq Database',
      action: async () => {
        const log = await this.service.refreshAutoEq()
        this.toast.show({ type: 'success', message: log })
      }
    }
  ] ]

  additionalPresetOptionLeft = {
    tooltip: 'Find your headphones (AutoEq)',
    icon: 'headphones' as const,
    iconSize: 12,
    action: () => this.openAutoEq()
  }

  public _presets: ParametricEqualizerPreset[]
  @Output() presetsChange = new EventEmitter<ParametricEqualizerPreset[]>()
  set presets (newPresets: ParametricEqualizerPreset[]) {
    this._presets = [
      newPresets.find(p => p.id === 'manual'),
      newPresets.find(p => p.id === 'flat'),
      ...newPresets.filter(p => ![ 'manual', 'flat' ].includes(p.id)).sort((a, b) => a.name > b.name ? 1 : -1)
    ].filter(p => !!p)
    this.presetsChange.emit(this.presets)
  }

  get presets () { return this._presets }

  public _selectedPreset: ParametricEqualizerPreset
  @Output() selectedPresetChange = new EventEmitter<ParametricEqualizerPreset>()
  set selectedPreset (preset: ParametricEqualizerPreset) {
    this._selectedPreset = preset
    this.selectedPresetChange.emit(preset)
    this.drafts = {}
    this.updateResponse()
  }

  get selectedPreset () { return this._selectedPreset }

  // Text being typed into a band field, keyed by `${index}.${field}`, so partial input isn't overwritten
  drafts: { [key: string]: string } = {}
  responsePath = ''
  zeroLineY = ParametricEqualizerComponent.graphHeight / 2
  graphRange = 12
  readonly graphWidth = 360
  readonly gridFrequencies = [ 100, 1000, 10000 ]

  private pushTimeout?: ReturnType<typeof setTimeout>

  constructor (
    public service: ParametricEqualizerService,
    public change: ChangeDetectorRef,
    public app: ApplicationService,
    public toast: ToastService,
    public dialog: MatDialog,
    public colors: ColorsService
  ) {
    super()
  }

  async ngOnInit () {
    await this.sync()
    this.setupEvents()
  }

  async sync () {
    await this.syncPresets()
  }

  public async syncPresets () {
    const [ presets, selectedPreset ] = await Promise.all([
      this.service.getPresets(),
      this.service.getSelectedPreset()
    ])
    this.presets = presets
    this.selectedPreset = presets.find(preset => preset.id === selectedPreset.id) ?? selectedPreset
    this.change.detectChanges()
  }

  private onPresetsChangedEventCallback: ParametricEqualizerPresetsChangedEventCallback
  protected setupEvents () {
    this.onPresetsChangedEventCallback = presets => {
      if (!presets) return
      this.presets = presets
      // Keep the edited copy if the user is mid-edit on Manual, otherwise pick up the stored version
      const stored = presets.find(p => p.id === this.selectedPreset?.id)
      if (stored && !this.pushTimeout) {
        this.selectedPreset = stored
      }
      this.change.detectChanges()
    }
    this.service.onPresetsChanged(this.onPresetsChangedEventCallback)
  }

  ngOnDestroy () {
    this.service.offPresetsChanged(this.onPresetsChangedEventCallback)
  }

  // MARK: - Presets

  async selectPreset (preset: ParametricEqualizerPreset) {
    this.selectedPreset = preset
    await this.service.selectPreset(preset)
  }

  async savePreset (name: string) {
    const { preamp, bands } = this.selectedPreset
    const existing = this.presets.filter(p => !p.isDefault).find(p => p.name === name)
    if (existing) {
      await this.service.updatePreset({ ...existing, preamp, bands }, { select: true })
    } else {
      await this.service.createPreset({ name, preamp, bands }, true)
    }
    await this.syncPresets()
  }

  async deletePreset () {
    if (!this.selectedPreset.isDefault) {
      await this.service.deletePreset(this.selectedPreset)
      await this.syncPresets()
    }
  }

  async openAutoEq () {
    const preset: ParametricEqualizerPreset | undefined = await this.dialog.open(AutoEqDialogComponent, {
      hasBackdrop: true,
      disableClose: false,
      data: { service: this.service }
    }).afterClosed().toPromise()
    if (preset) {
      await this.syncPresets()
      this.toast.show({ type: 'success', message: `Loaded ${preset.name}` })
    }
  }

  // MARK: - Editing

  // Edits always go to the Manual preset (same behaviour as the Advanced Equalizer)
  private edit (mutate: (preset: ParametricEqualizerPreset) => void) {
    const manual = this.presets.find(p => p.id === 'manual')
    const edited: ParametricEqualizerPreset = {
      ...manual,
      preamp: this.selectedPreset.preamp,
      bands: this.selectedPreset.bands.map(band => ({ ...band }))
    }
    mutate(edited)
    Object.assign(manual, { preamp: edited.preamp, bands: edited.bands })
    const drafts = this.drafts
    this.selectedPreset = manual
    this.drafts = drafts
    this.change.detectChanges()
    this.schedulePush()
  }

  private schedulePush () {
    if (this.pushTimeout) clearTimeout(this.pushTimeout)
    this.pushTimeout = setTimeout(async () => {
      const preset = this.selectedPreset
      try {
        await this.service.updatePreset(preset, { select: true })
      } finally {
        this.pushTimeout = undefined
      }
    }, 150)
  }

  setPreamp (value: number) {
    this.edit(preset => { preset.preamp = this.round(this.clamp(value, this.limits.preamp), 1) })
  }

  addBand () {
    if (this.selectedPreset.bands.length >= this.maxBands) return
    this.edit(preset => {
      preset.bands.push({ type: 'PK', frequency: 1000, gain: 0, q: 1.41, enabled: true })
    })
  }

  removeBand (index: number) {
    this.edit(preset => { preset.bands.splice(index, 1) })
    this.drafts = {}
  }

  toggleBand (index: number) {
    this.edit(preset => { preset.bands[index].enabled = !preset.bands[index].enabled })
  }

  cycleType (index: number) {
    this.edit(preset => {
      const band = preset.bands[index]
      const next = FILTER_TYPES[(FILTER_TYPES.findIndex(t => t.type === band.type) + 1) % FILTER_TYPES.length]
      band.type = next.type
      // AutoEq shelves use Q 0.7, a sensible default when switching from a narrow peak
      if (next.type !== 'PK' && band.q > 2) band.q = 0.7
    })
  }

  typeLabel (type: ParametricEqualizerFilterType) {
    return FILTER_TYPES.find(t => t.type === type)?.label ?? type
  }

  typeName (type: ParametricEqualizerFilterType) {
    return FILTER_TYPES.find(t => t.type === type)?.name ?? type
  }

  fieldText (index: number, field: BandField) {
    const draft = this.drafts[`${index}.${field}`]
    if (draft !== undefined) return draft
    const value = this.selectedPreset.bands[index][field]
    switch (field) {
      case 'frequency': return `${Math.round(value)}`
      case 'gain': return value.toFixed(1)
      case 'q': return value.toFixed(2)
    }
  }

  fieldChanged (index: number, field: BandField, text: string) {
    this.drafts[`${index}.${field}`] = text
    const value = this.parseField(field, text)
    if (value !== undefined) {
      this.edit(preset => { preset.bands[index][field] = value })
    }
  }

  fieldCommitted (index: number, field: BandField) {
    delete this.drafts[`${index}.${field}`]
    this.change.detectChanges()
  }

  fieldInvalid (index: number, field: BandField) {
    const draft = this.drafts[`${index}.${field}`]
    return draft !== undefined && this.parseField(field, draft) === undefined
  }

  private parseField (field: BandField, text: string): number | undefined {
    const normalized = text.trim().toLowerCase().replace(/\s*(hz|db)$/, '')
    let value = Number(normalized.endsWith('k') ? normalized.slice(0, -1) : normalized)
    if (normalized.endsWith('k')) value *= 1000
    if (!normalized.length || !Number.isFinite(value)) return undefined
    const { min, max } = this.limits[field]
    if (value < min || value > max) return undefined
    return value
  }

  private clamp (value: number, range: { min: number, max: number }) {
    return Math.min(Math.max(value, range.min), range.max)
  }

  private round (value: number, decimals: number) {
    const factor = 10 ** decimals
    return Math.round(value * factor) / factor
  }

  bandTracker (index: number) {
    return index
  }

  screenValue (gain: number) {
    return `${gain > 0 ? '+' : ''}${gain.toFixed(1)}dB`
  }

  performHapticFeedback () {
    this.app.haptic()
  }

  // MARK: - Response graph

  graphX (frequency: number) {
    return Math.log10(frequency / 20) / Math.log10(20000 / 20) * this.graphWidth
  }

  graphY (db: number) {
    const h = ParametricEqualizerComponent.graphHeight
    return h / 2 - (db / this.graphRange) * (h / 2 - 4)
  }

  private updateResponse () {
    const bands = this.selectedPreset?.bands ?? []
    const points = 160
    const frequencies = [ ...Array(points) ].map((_, i) => 20 * Math.pow(1000, i / (points - 1)))
    const response = magnitudeResponse(bands, frequencies)
    const peak = Math.max(6, ...response.map(Math.abs))
    this.graphRange = Math.min(24, Math.ceil(peak / 6) * 6)
    this.zeroLineY = this.graphY(0)
    this.responsePath = response
      .map((db, i) => `${i === 0 ? 'M' : 'L'}${this.graphX(frequencies[i]).toFixed(1)},${this.graphY(db).toFixed(1)}`)
      .join(' ')
  }

  get graphRangeLabel () {
    return `±${this.graphRange}dB`
  }

  frequencyLabel (frequency: number) {
    return frequency >= 1000 ? `${frequency / 1000}k` : `${frequency}`
  }
}
