// Debug logging utility
const debugLog = {
  log: (message: string, type: 'info' | 'error' | 'success' = 'info') => {
    const logEl = document.getElementById('debug-log')
    if (!logEl) return

    const entry = document.createElement('div')
    entry.className = `dev-log-entry ${type}`
    entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`

    logEl.appendChild(entry)
    logEl.scrollTop = logEl.scrollHeight

    // Keep only last 20 entries
    while (logEl.children.length > 20) {
      logEl.removeChild(logEl.firstChild!)
    }
  }
}

// Initialize app
const init = () => {
  debugLog.log('App initialized', 'success')

  // Setup event listeners for dev tools
  document.getElementById('use-canvas')?.addEventListener('click', () => {
    debugLog.log('Canvas mode selected', 'info')
    // TODO: Implement canvas rendering
  })

  document.getElementById('use-svg')?.addEventListener('click', () => {
    debugLog.log('SVG mode selected', 'info')
    // TODO: Implement SVG rendering
  })

  document.getElementById('clear-btn')?.addEventListener('click', () => {
    debugLog.log('Cleared', 'info')
    // TODO: Clear canvas/SVG
  })

  document.getElementById('reset-btn')?.addEventListener('click', () => {
    debugLog.log('Reset', 'info')
    // TODO: Reset to initial state
  })
}

document.addEventListener('DOMContentLoaded', init)
