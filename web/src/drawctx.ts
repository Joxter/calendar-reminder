// The drawing seam. The renderer (timeline.ts) talks ONLY to this interface, so
// the same code drives Canvas2D on the web and NSBezierPath/NSString.draw in Swift.
//
// Mapping:
//   Path.moveTo / lineTo / arc   ≈ NSBezierPath move(to:) / line(to:) / appendArc
//   DrawCtx.stroke / fill        ≈ NSBezierPath.stroke() / .fill()
//   DrawCtx.fillRect             ≈ NSBezierPath(rect:).fill()
//   DrawCtx.fillText             ≈ (s as NSString).draw(at:withAttributes:)
//   DrawCtx.measureText          ≈ s.size(withAttributes:)
//
// Coordinates: y=0 at top, increasing downward — matches the flipped TimelineView.

export type FontWeight = 'regular' | 'medium' | 'semibold' | 'bold' | 'black'

export interface Font {
  size: number
  weight: FontWeight
  mono: boolean
}

export function font(size: number, weight: FontWeight = 'regular', mono = false): Font {
  return { size, weight, mono }
}

export type LineCap = 'butt' | 'round'

export interface Path {
  moveTo(x: number, y: number): Path
  lineTo(x: number, y: number): Path
  /// Angles in degrees. `clockwise` matches NSBezierPath.appendArc convention.
  arc(cx: number, cy: number, r: number, startDeg: number, endDeg: number, clockwise: boolean): Path
}

export interface TextSize {
  width: number
  height: number
}

export interface DrawCtx {
  beginPath(): Path
  stroke(path: Path, color: string, width: number, alpha?: number, cap?: LineCap): void
  fill(path: Path, color: string, alpha?: number): void
  fillRect(x: number, y: number, w: number, h: number, color: string, alpha?: number): void
  /// Draws text with its top-left at (x, y) — matches NSString.draw(at:) in a flipped view.
  fillText(text: string, x: number, y: number, f: Font, color: string, alpha?: number): void
  measureText(text: string, f: Font): TextSize
}
