import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, rmSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const output = fileURLToPath(
  new URL('../public/options.json', import.meta.url),
);
const source =
  process.env.PARED_OPTIONS_JSON ??
  `${execFileSync(
    'nix',
    ['build', `${root}#docs-json`, '--no-link', '--print-out-paths'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] },
  ).trim()}/share/doc/nixos/options.json`;
mkdirSync(fileURLToPath(new URL('../public/', import.meta.url)), {
  recursive: true,
});
rmSync(output, { force: true });
copyFileSync(source, output);
chmodSync(output, 0o644);
