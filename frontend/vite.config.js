import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')

  return {
    plugins: [react()],
    server: {
      port: 3000,
      // Proxy only in development — API runs locally on 8080
      proxy: mode === 'development' ? {
        '/api': {
          target: 'http://localhost:8080',
          changeOrigin: true,
        },
      } : undefined,
    },
    define: {
      // Make env available at build time
      __APP_ENV__: JSON.stringify(env.VITE_APP_ENV || mode),
    },
  }
})
