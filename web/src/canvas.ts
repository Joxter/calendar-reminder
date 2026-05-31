// Canvas2D-backed DrawCtx. This is the only web-specific rendering file; it has
// no Swift counterpart (the Swift port implements DrawCtx over NSBezierPath).

import { DrawCtx, Font, FontWeight, LineCap, Path, TextSize } from './drawctx'

const weightCSS: Record<FontWeight, string> = {
  regular: '400',
  medium: '500',
  semibold: '600',
  bold: '700',
  black: '900',
}

const sansStack = `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
const monoStack = `ui-monospace, 'SF Mono', Menlo, Monaco, monospace`

function fontCSS(f: Font): string {
  return `${weightCSS[f.weight]} ${f.size}px ${f.mono ? monoStack : sansStack}`
}

const DEG = Math.PI / 180

class CanvasPath implements Path {
  constructor(private ctx: CanvasRenderingContext2D) {
    ctx.beginPath()
  }
  moveTo(x: number, y: number): Path {
    this.ctx.moveTo(x, y)
    return this
  }
  lineTo(x: number, y: number): Path {
    this.ctx.lineTo(x, y)
    return this
  }
  arc(cx: number, cy: number, r: number, startDeg: number, endDeg: number, clockwise: boolean): Path {
    // Canvas arc: anticlockwise=true means decreasing angle (short path from start to end).
    // clockwise=true here means we want the short increasing-angle path, so anticlockwise=false.
    // Swift port note: in a flipped NSBezierPath, clockwise:false produces the same short arc
    // (the flipped view reverses the sweep direction relative to the DrawCtx convention).
    this.ctx.arc(cx, cy, r, startDeg * DEG, endDeg * DEG, !clockwise)
    return this
  }
}

export class CanvasDrawCtx implements DrawCtx {
  private ctx: CanvasRenderingContext2D

  constructor(private canvas: HTMLCanvasElement) {
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('2D context unavailable')
    this.ctx = ctx
    this.setupHiDPI()
    this.ctx.textBaseline = 'top'
  }

  /// Scales the backing store for crisp text on retina displays.
  setupHiDPI(): void {
    const dpr = window.devicePixelRatio || 1
    const w = this.canvas.clientWidth || parseInt(this.canvas.style.width) || this.canvas.width
    const h = this.canvas.clientHeight || parseInt(this.canvas.style.height) || this.canvas.height
    this.canvas.width = Math.round(w * dpr)
    this.canvas.height = Math.round(h * dpr)
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.ctx.textBaseline = 'top'
  }

  clear(): void {
    this.ctx.save()
    this.ctx.setTransform(1, 0, 0, 1, 0, 0)
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
    this.ctx.restore()
  }

  beginPath(): Path {
    return new CanvasPath(this.ctx)
  }

  stroke(_path: Path, color: string, width: number, alpha = 1, cap: LineCap = 'butt'): void {
    this.ctx.globalAlpha = alpha
    this.ctx.strokeStyle = color
    this.ctx.lineWidth = width
    this.ctx.lineCap = cap
    this.ctx.stroke()
    this.ctx.globalAlpha = 1
  }

  fill(_path: Path, color: string, alpha = 1): void {
    this.ctx.globalAlpha = alpha
    this.ctx.fillStyle = color
    this.ctx.fill()
    this.ctx.globalAlpha = 1
  }

  fillRect(x: number, y: number, w: number, h: number, color: string, alpha = 1): void {
    this.ctx.globalAlpha = alpha
    this.ctx.fillStyle = color
    this.ctx.fillRect(x, y, w, h)
    this.ctx.globalAlpha = 1
  }

  fillText(text: string, x: number, y: number, f: Font, color: string, alpha = 1): void {
    this.ctx.globalAlpha = alpha
    this.ctx.fillStyle = color
    this.ctx.font = fontCSS(f)
    this.ctx.fillText(text, x, y)
    this.ctx.globalAlpha = 1
  }

  measureText(text: string, f: Font): TextSize {
    this.ctx.font = fontCSS(f)
    const m = this.ctx.measureText(text)
    const ascent = m.fontBoundingBoxAscent ?? f.size * 0.8
    const descent = m.fontBoundingBoxDescent ?? f.size * 0.2
    return { width: m.width, height: ascent + descent }
  }
}
