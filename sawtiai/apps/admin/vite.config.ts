import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Relative base so the static build can be hosted on any path (e.g. GitHub Pages).
  base: './',
  test: { environment: 'jsdom', globals: true },
})
