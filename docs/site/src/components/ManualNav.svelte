<script lang="ts">
import House from '@lucide/svelte/icons/house';
import { IsMounted } from 'runed';
import { innerWidth, scrollY } from 'svelte/reactivity/window';
import BrandIcon from './BrandIcon.svelte';
import ModeToggle from './ModeToggle.svelte';

const sections = [
  { href: '#getting-started', label: 'Getting started' },
  { href: '#feature-choices', label: 'Features & profile setup' },
  { href: '#model-cleanup', label: 'Remove & download models' },
  { href: '#command-line', label: 'Command line' },
  { href: '#quick-start', label: 'Nix configuration' },
  { href: '#sec-options', label: 'Nix option reference' },
];

const mounted = new IsMounted();
const activeHref = $derived.by(() => {
  if (!mounted.current || scrollY.current === undefined) return null;
  const offset = (innerWidth.current ?? 0) >= 1024 ? 120 : 180;
  let active: string | null = null;
  for (const section of sections) {
    const element = document.getElementById(section.href.slice(1));
    if (element && element.getBoundingClientRect().top <= offset) {
      active = section.href;
    }
  }
  return active;
});
</script>

<header class="manual-nav">
  <div class="nav-brand">
    <a class="brand" href={import.meta.env.BASE_URL} aria-label="Pared home">
      <BrandIcon size={32} />
      pared
    </a>
    <ModeToggle />
  </div>
  <a class="nav-home" href={import.meta.env.BASE_URL}>
    <House size={16} aria-hidden="true" />
    Back to the overview
  </a>
  <nav class="section-navigation" aria-label="Documentation sections">
    <p class="nav-label">The manual</p>
    <ul>
      {#each sections as section (section.href)}
        <li>
          <a
            class="nav-link"
            class:active={activeHref === section.href}
            aria-current={activeHref === section.href ? 'location' : undefined}
            href={section.href}
            >{section.label}</a
          >
        </li>
      {/each}
    </ul>
  </nav>
  <a class="nav-source" href="https://github.com/4evy/pared">GitHub</a>
</header>
