import { Component, OnInit, OnDestroy, ChangeDetectorRef } from '@angular/core'
import { MatDialogRef } from '@angular/material/dialog'
import { ColorsService } from '@eqmac/components'
import { ApplicationService } from '../../../../../services/app.service'
import { ParametricEqualizerService, AutoEqModel, AutoEqResult } from '../parametric-equalizer.service'

// Lists live inside the dialog (no floating dropdowns), so they can't be cut off by a short app window
@Component({
  selector: 'eqm-autoeq-dialog',
  templateUrl: './autoeq-dialog.component.html',
  styleUrls: [ './autoeq-dialog.component.scss' ]
})
export class AutoEqDialogComponent implements OnInit, OnDestroy {
  query = ''
  brands: string[] = []
  // Brand being browsed when there is no search text
  browsedBrand?: string
  models: AutoEqModel[] = []
  selectedModel?: AutoEqModel
  selectedResult?: AutoEqResult

  status?: string
  error?: string
  busy = false

  private searchTimeout?: ReturnType<typeof setTimeout>
  private searchCounter = 0

  constructor (
    public dialogRef: MatDialogRef<AutoEqDialogComponent>,
    public service: ParametricEqualizerService,
    public app: ApplicationService,
    public colors: ColorsService,
    private readonly change: ChangeDetectorRef
  ) {}

  ngOnInit () {
    return this.loadBrands()
  }

  ngOnDestroy () {
    if (this.searchTimeout) clearTimeout(this.searchTimeout)
  }

  get mode (): 'brands' | 'models' {
    return this.query.trim().length || this.browsedBrand ? 'models' : 'brands'
  }

  async loadBrands () {
    await this.run('Loading the AutoEq database…', async () => {
      this.brands = await this.service.getAutoEqBrands()
    })
  }

  queryChanged (query: string) {
    this.query = query ?? ''
    this.browsedBrand = undefined
    this.clearSelection()
    if (this.searchTimeout) clearTimeout(this.searchTimeout)
    if (!this.query.trim().length) {
      this.models = []
      this.change.detectChanges()
      return
    }
    this.searchTimeout = setTimeout(() => this.search(), 200)
  }

  private async search () {
    const id = ++this.searchCounter
    const query = this.query
    try {
      const models = await this.service.searchAutoEq(query)
      // Ignore responses for queries the user has already typed past
      if (id !== this.searchCounter) return
      this.models = models
      this.error = undefined
    } catch (err) {
      if (id === this.searchCounter) this.error = this.errorMessage(err)
    }
    this.change.detectChanges()
  }

  async browseBrand (brand: string) {
    this.browsedBrand = brand
    this.clearSelection()
    this.models = []
    await this.run(`Loading ${brand} models…`, async () => {
      const models = await this.service.getAutoEqModels(brand)
      this.models = models.map(model => ({ ...model, brand }))
    })
  }

  backToBrands () {
    this.browsedBrand = undefined
    this.models = []
    this.clearSelection()
    this.change.detectChanges()
  }

  selectModel (model: AutoEqModel) {
    this.selectedModel = model
    // Entries come sorted by AutoEq's preferred measurement source, so the first one is the default
    this.selectedResult = model.entries[0]
    this.change.detectChanges()
  }

  selectResult (result: AutoEqResult) {
    this.selectedResult = result
    this.change.detectChanges()
  }

  modelLabel (model: AutoEqModel) {
    return this.browsedBrand ? model.model : `${model.brand} ${model.model}`
  }

  async load (result = this.selectedResult) {
    if (!result || this.busy) return
    let preset
    await this.run(`Loading ${result.name}…`, async () => {
      preset = await this.service.loadAutoEqResult(result)
    })
    if (preset) this.dialogRef.close(preset)
  }

  openAutoEq () {
    return this.app.openURL(new URL('https://github.com/jaakkopasanen/AutoEq'))
  }

  close () {
    this.dialogRef.close()
  }

  trackByIndex (index: number) {
    return index
  }

  private clearSelection () {
    this.selectedModel = undefined
    this.selectedResult = undefined
  }

  private errorMessage (err: any) {
    return typeof err === 'string' ? err : (err?.message ?? 'Something went wrong')
  }

  private async run (status: string, task: () => Promise<void>) {
    this.busy = true
    this.status = status
    this.error = undefined
    this.change.detectChanges()
    try {
      await task()
    } catch (err) {
      this.error = this.errorMessage(err)
    } finally {
      this.busy = false
      this.status = undefined
      this.change.detectChanges()
    }
  }
}
