import {
  Component,
  OnInit,
  ViewChild,
  AfterContentInit,
  HostListener
} from '@angular/core'
import { UtilitiesService } from './services/utilities.service'
import { UIService } from './services/ui.service'
import { FadeInOutAnimation, FromTopAnimation } from '@eqmac/components'
import { MatDialog, MatDialogRef } from '@angular/material/dialog'
import { TransitionService } from './services/transitions.service'
import { ApplicationService } from './services/app.service'
import { SettingsService, IconMode } from './sections/settings/settings.service'
import { ToastService } from './services/toast.service'
import { OptionsDialogComponent } from './components/options-dialog/options-dialog.component'
import { Option, Options } from './components/options/options.component'
import { HeaderComponent } from './sections/header/header.component'
import { VolumeBoosterBalanceComponent } from './sections/volume/booster-balance/volume-booster-balance.component'
import { EqualizersComponent } from './sections/effects/equalizers/equalizers.component'
import { OutputsComponent } from './sections/outputs/outputs.component'

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: [ './app.component.scss' ],
  animations: [ FadeInOutAnimation, FromTopAnimation ]
})

export class AppComponent implements OnInit, AfterContentInit {
  @ViewChild('container', { static: true }) container
  @ViewChild('header', { static: true }) header: HeaderComponent
  @ViewChild('volumeBoosterBalance', { static: false }) volumeBoosterBalance: VolumeBoosterBalanceComponent
  @ViewChild('equalizers', { static: false }) equalizers: EqualizersComponent
  @ViewChild('outputs', { static: false }) outputs: OutputsComponent

  loaded = false
  animationDuration = 500
  animationFps = 30

  showDropdownSections = {
    settings: false,
    help: false
  }

  private containerWidth = 400
  private containerHeight = 400
  get containerStyle () {
    const style: any = {}

    style.width = `${this.containerWidth / this.ui.scale}px`
    style.height = `${this.containerHeight / this.ui.scale}px`
    style.transform = `scale(${this.ui.scale})`

    const cdkOverlays = document.getElementsByClassName('cdk-overlay-pane')
    for (let i = 0; i < cdkOverlays.length; i++) {
      cdkOverlays[i].setAttribute('style', `transform: scale(${this.ui.scale.toFixed(2)}); width: ${Math.round(90 / this.ui.scale)}vw`)
    }
    return style
  }

  constructor (
    public utils: UtilitiesService,
    public ui: UIService,
    public dialog: MatDialog,
    public transitions: TransitionService,
    public app: ApplicationService,
    public settings: SettingsService,
    public toast: ToastService
  ) {
    this.app.ref = this
  }

  get minHeight () {
    const divider = 3

    const {
      volumeFeatureEnabled, balanceFeatureEnabled,
      equalizersFeatureEnabled,
      outputFeatureEnabled
    } = this.ui.settings
    let minHeight = this.header.height + divider +
      ((volumeFeatureEnabled || balanceFeatureEnabled) ? (this.volumeBoosterBalance.height + divider) : 0) +
      (equalizersFeatureEnabled ? (this.equalizers.height + divider) : 0) +
      (outputFeatureEnabled ? this.outputs.height : 0)

    const dropdownSection = document.getElementById('dropdown-section')
    if (dropdownSection) {
      const dropdownHeight = dropdownSection.offsetHeight + this.header.height + divider
      if (dropdownHeight > minHeight) {
        minHeight = dropdownHeight
      }
    }

    // Grow the window so open dialogs are never cut off
    const dialogHeight = this.openDialogHeight
    if (dialogHeight > minHeight) {
      minHeight = dialogHeight
    }

    return minHeight
  }

  get openDialogHeight () {
    const margin = 40
    const panes = Array.from(document.querySelectorAll<HTMLElement>('.cdk-overlay-pane'))
    return panes.reduce((height, pane) => Math.max(height, pane.offsetHeight ? pane.offsetHeight + margin : 0), 0)
  }

  get minWidth () {
    return 400
  }

  get maxHeight () {
    const divider = 3

    const {
      volumeFeatureEnabled, balanceFeatureEnabled,
      equalizersFeatureEnabled,
      outputFeatureEnabled
    } = this.ui.settings
    let maxHeight = this.header.height + divider +
      ((volumeFeatureEnabled || balanceFeatureEnabled) ? (this.volumeBoosterBalance.height + divider) : 0) +
      (equalizersFeatureEnabled ? (this.equalizers.maxHeight + divider) : 0) +
      (outputFeatureEnabled ? this.outputs.height : 0)

    const dropdownSection = document.getElementById('dropdown-section')
    if (dropdownSection) {
      const dropdownHeight = dropdownSection.offsetHeight + this.header.height + divider
      if (dropdownHeight > maxHeight) {
        maxHeight = dropdownHeight
      }
    }

    return maxHeight
  }

  async ngOnInit () {
    await this.sync()
    await this.fixUIMode()
    this.startDimensionsSync()
  }

  async ngAfterContentInit () {
    await this.utils.delay(this.animationDuration)
    this.loaded = true
    await this.utils.delay(1000)
    this.ui.loaded()
  }

  async sync () {
    await Promise.all([
      this.getTransitionSettings()
    ])
  }

  async startDimensionsSync () {
    this.handleWindowResize()
    // Resize for dialogs right away instead of waiting for the next interval tick
    const syncAfterRender = () => setTimeout(() => this.syncMinHeight(), 50)
    this.dialog.afterOpened.subscribe(syncAfterRender)
    this.dialog.afterAllClosed.subscribe(syncAfterRender)
    setInterval(() => {
      this.syncMinHeight()
      this.syncMaxHeight()
    }, 1000)
  }

  private previousMinHeight: number
  async syncMinHeight () {
    if (!this.previousMinHeight) {
      this.previousMinHeight = this.minHeight
      await this.ui.setMinHeight({ minHeight: this.minHeight })
      return
    }

    const diff = this.minHeight - this.previousMinHeight
    this.previousMinHeight = this.minHeight
    if (diff !== 0) {
      this.ui.onMinHeightChanged.emit()
      await this.ui.setMinHeight({ minHeight: this.minHeight })
    }

    if (diff < 0) {
      this.ui.changeHeight({ diff })
    }
  }

  private previousMaxHeight: number
  async syncMaxHeight () {
    if (!this.previousMaxHeight) {
      this.previousMaxHeight = this.maxHeight
      await this.ui.setMaxHeight({ maxHeight: this.maxHeight })
      return
    }

    const diff = this.maxHeight - this.previousMaxHeight
    this.previousMaxHeight = this.maxHeight
    await this.ui.setMaxHeight({ maxHeight: this.maxHeight })
    if (diff > 0) {
      // this.ui.changeHeight({ diff })
    }
  }

  private windowResizeHandlerTimer: number
  @HostListener('window:resize')
  handleWindowResize () {
    if (this.windowResizeHandlerTimer) {
      clearTimeout(this.windowResizeHandlerTimer)
    }

    this.windowResizeHandlerTimer = setTimeout(async () => {
      const [ height, width ] = await Promise.all([
        this.ui.getHeight(),
        this.ui.getWidth()
      ])

      this.containerHeight = height
      this.containerWidth = width

      setTimeout(() => {
        this.ui.dimensionsChanged.emit()
      }, 100)
    }, 100) as any
  }

  async getTransitionSettings () {
    const settings = await this.transitions.getSettings()
    this.animationDuration = settings.duration
    this.animationFps = settings.fps
  }

  toggleDropdownSection (section: string) {
    for (const key in this.showDropdownSections) {
      this.showDropdownSections[key] = key === section ? !this.showDropdownSections[key] : false
    }
  }

  openDropdownSection (section: string) {
    for (const key in this.showDropdownSections) {
      this.showDropdownSections[key] = key === section
    }
  }

  async fixUIMode () {
    const [ mode, iconMode ] = await Promise.all([
      this.ui.getMode(),
      this.settings.getIconMode()
    ])

    if (mode === 'popover' && iconMode === IconMode.dock) {
      await this.ui.setMode('window')
    }
  }

  closeDropdownSection (section: string, event?: MouseEvent) {
    // if (event && event.target && ['backdrop', 'mat-dialog'].some(e => event.target.className.includes(e))) return
    if (this.dialog.openDialogs.length > 0) return
    if (section in this.showDropdownSections) {
      this.showDropdownSections[section] = false
    }
  }
}
