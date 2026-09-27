<script lang="ts">
import { onMount } from 'svelte';
import ModeToggle from './ModeToggle.svelte';

const sections = [
  { href: '#sec-options', label: 'Option reference' },
  { href: '#quick-start', label: 'Quick start' },
];

let activeHref = $state<string | null>(null);

onMount(() => {
  const updateActiveSection = () => {
    const offset = window.innerWidth >= 1024 ? 120 : 180;
    let active: string | null = null;
    for (const section of sections) {
      const element = document.getElementById(section.href.slice(1));
      if (element && element.getBoundingClientRect().top <= offset) {
        active = section.href;
      }
    }
    activeHref = active;
  };

  updateActiveSection();
  window.addEventListener('scroll', updateActiveSection, { passive: true });
  window.addEventListener('resize', updateActiveSection);
  return () => {
    window.removeEventListener('scroll', updateActiveSection);
    window.removeEventListener('resize', updateActiveSection);
  };
});
</script>

<header class="manual-nav">
  <div class="nav-brand">
    <a class="brand" href="#content">Pared <span>docs</span></a>
    <ModeToggle />
  </div>
  <nav class="section-navigation" aria-label="Documentation sections">
    <p class="nav-label">Documentation</p>
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
  <a class="nav-source" href="https://github.com/4evy/pared">GitHub ↗</a>
</header>
