import { defineConfig } from 'vite';
import { VitePWA }      from '@vite-pwa/plugin';

export default defineConfig({
  // PowerSync Web SDK uses SharedArrayBuffer — needs COOP/COEP headers.
  // Vercel serves these automatically via vercel.json headers below.
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'icons/*.png'],
      manifest: {
        name:             'Afya Nyumbani',
        short_name:       'Afya Nyumbani',
        description:      'Community outbreak signal reporting — works offline',
        theme_color:      '#085041',
        background_color: '#F1F5F9',
        display:          'standalone',
        orientation:      'portrait',
        start_url:        '/',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
        ]
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,wasm}'],
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/.*\.supabase\.co\/.*/i,
            handler:    'NetworkFirst',
            options:    { cacheName: 'supabase-api', networkTimeoutSeconds: 10 }
          }
        ]
      }
    })
  ],
  optimizeDeps: {
    exclude: ['@powersync/web']
  },
  worker: {
    format: 'es'
  }
});
