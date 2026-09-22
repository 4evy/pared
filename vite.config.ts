import tailwindcss from '@tailwindcss/vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

function resolveRevision() {
  if (process.env.PARED_REVISION) return process.env.PARED_REVISION;

  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return 'dev';
  }
}

export default defineConfig(({ command, isPreview }) => ({
  root: fileURLToPath(new URL('./docs/site', import.meta.url)),
  base:
    process.env.PARED_BASE_URL ??
    (command === 'build' || isPreview ? '/pared/' : '/'),
  define: {
    __PARED_REVISION__: JSON.stringify(resolveRevision()),
  },
  plugins: [svelte(), tailwindcss()],
}));
