<script lang="ts">
import Moon from '@lucide/svelte/icons/moon';
import Sun from '@lucide/svelte/icons/sun';
import { mode, toggleMode } from 'mode-watcher';
import { focusClass } from '../classes';

const nextMode = $derived(mode.current === 'dark' ? 'light' : 'dark');
const label = $derived(`Switch to ${nextMode} mode`);
</script>

<button
  type="button"
  class={`icon-button ${focusClass}`}
  aria-label={label}
  title={label}
  onclick={toggleMode}
>
  {#if mode.current === 'dark'}
    <Sun size={18} />
  {:else}
    <Moon size={18} />
  {/if}
</button>
