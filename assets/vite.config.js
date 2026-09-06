import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath } from 'node:url';
export default defineConfig({plugins:[svelte(),tailwindcss()],resolve:{alias:{$lib:fileURLToPath(new URL('./js/lib',import.meta.url))}},build:{outDir:'../priv/static/assets',emptyOutDir:true,lib:{entry:'js/app.js',formats:['es'],fileName:()=> 'js/app.js',cssFileName:'app'},rollupOptions:{output:{assetFileNames:asset=>asset.names?.some(n=>n.endsWith('.css'))?'css/app.css':'[name][extname]'}}}});
