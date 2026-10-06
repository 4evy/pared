<script lang="ts">
import { ModeWatcher } from 'mode-watcher';
import Documentation from './components/Documentation.svelte';
import LandingPage from './components/LandingPage.svelte';

let { page }: { page: 'home' | 'docs' } = $props();
</script>

<ModeWatcher
  defaultMode="system"
  themeColors={{ light: '#fcfafc', dark: '#19161c' }}
/>
{#if page === 'docs'}
  <Documentation />
{:else}
  <LandingPage />
{/if}
