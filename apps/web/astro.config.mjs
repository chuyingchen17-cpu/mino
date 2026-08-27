// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// 根域名保留给产品页（见 Docs/CloudflareDeployment.md），API 在 api.mino.pet。
// 没有 UI 框架集成：交互少且简单，用原生 <script> 写，客户端不加载任何运行时。
export default defineConfig({
  site: 'https://mino.pet',
  output: 'static',
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
  build: {
    // 营销页的 CSS 很小，内联掉可以省一个首屏请求。
    inlineStylesheets: 'auto',
  },
});
