import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: './',

  plugins: [
    react()
  ],

  resolve: {
    dedupe: ['react', 'react-dom']
  },

  optimizeDeps: {
    include: ['react', 'react-dom']
  },

  build: {
    chunkSizeWarningLimit: 1000,
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('three')) return 'three'
            if (id.includes('@react-three')) return 'react-three'
            return 'vendor'
          }
        }
      }
    }
  }
})
