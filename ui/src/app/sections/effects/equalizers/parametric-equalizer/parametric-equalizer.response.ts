import { ParametricEqualizerBand } from './parametric-equalizer.service'

// Magnitude response (dB) of the enabled bands, using the RBJ Audio EQ Cookbook biquads,
// which is what AutoEq designs its filters with and what AVAudioUnitEQ reproduces natively.
export function magnitudeResponse (bands: ParametricEqualizerBand[], frequencies: number[], sampleRate = 48000): number[] {
  const response = frequencies.map(() => 0)
  for (const band of bands) {
    if (!band.enabled || band.gain === 0) continue
    const { b, a } = coefficients(band, sampleRate)
    frequencies.forEach((frequency, i) => {
      response[i] += 20 * Math.log10(magnitude(b, frequency, sampleRate) / magnitude(a, frequency, sampleRate))
    })
  }
  return response
}

function coefficients (band: ParametricEqualizerBand, sampleRate: number) {
  const frequency = Math.min(band.frequency, sampleRate * 0.49)
  const A = Math.pow(10, band.gain / 40)
  const w0 = 2 * Math.PI * frequency / sampleRate
  const cos = Math.cos(w0)
  const alpha = Math.sin(w0) / (2 * band.q)
  const shelf = 2 * Math.sqrt(A) * alpha
  switch (band.type) {
    case 'LSC': return {
      b: [ A * ((A + 1) - (A - 1) * cos + shelf), 2 * A * ((A - 1) - (A + 1) * cos), A * ((A + 1) - (A - 1) * cos - shelf) ],
      a: [ (A + 1) + (A - 1) * cos + shelf, -2 * ((A - 1) + (A + 1) * cos), (A + 1) + (A - 1) * cos - shelf ]
    }
    case 'HSC': return {
      b: [ A * ((A + 1) + (A - 1) * cos + shelf), -2 * A * ((A - 1) + (A + 1) * cos), A * ((A + 1) + (A - 1) * cos - shelf) ],
      a: [ (A + 1) - (A - 1) * cos + shelf, 2 * ((A - 1) - (A + 1) * cos), (A + 1) - (A - 1) * cos - shelf ]
    }
    default: return {
      b: [ 1 + alpha * A, -2 * cos, 1 - alpha * A ],
      a: [ 1 + alpha / A, -2 * cos, 1 - alpha / A ]
    }
  }
}

function magnitude (k: number[], frequency: number, sampleRate: number) {
  const w = 2 * Math.PI * frequency / sampleRate
  const re = k[0] + k[1] * Math.cos(w) + k[2] * Math.cos(2 * w)
  const im = -(k[1] * Math.sin(w) + k[2] * Math.sin(2 * w))
  return Math.sqrt(re * re + im * im)
}
