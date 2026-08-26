// @ts-check
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// 根域名保留给产品页（见 Docs/CloudflareDeployment.md），API 在 api.mino.pet。
export default defineConfig({
  site: 'https://mino.pet',
  output: 'static',
  integrations: [react(), sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
  build: {
    // 营销页的 CSS 很小，内联掉可以省一个首屏请求。
    inlineStylesheets: 'auto',
  },
});
