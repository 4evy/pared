<script lang="ts">
import AppWindow from '@lucide/svelte/icons/app-window';
import Check from '@lucide/svelte/icons/check';
import Code from '@lucide/svelte/icons/code';
import Copy from '@lucide/svelte/icons/copy';
import Download from '@lucide/svelte/icons/download';
import Package from '@lucide/svelte/icons/package';
import Terminal from '@lucide/svelte/icons/terminal';
import { onDestroy, untrack } from 'svelte';
import {
  appDownload,
  releasesPage,
  homebrewCommand,
  installCommand,
  nixCommand,
} from '../install';

type Method = 'app' | 'script' | 'brew' | 'nix';
let {
  compact = false,
  initialMethod = 'script',
}: {
  compact?: boolean;
  initialMethod?: Method;
} = $props();
let method = $state<Method>(untrack(() => initialMethod));
let copyState = $state<'idle' | 'copied' | 'error'>('idle');
let resetTimer: ReturnType<typeof setTimeout> | undefined;
const commands = {
  app: '',
  script: installCommand,
  brew: homebrewCommand,
  nix: nixCommand,
};
const command = $derived(compact ? installCommand : commands[method]);

function selectMethod(next: Method) {
  method = next;
  copyState = 'idle';
  clearTimeout(resetTimer);
}

async function copyCommand() {
  clearTimeout(resetTimer);
  const copiedCommand = command;
  try {
    await navigator.clipboard.writeText(copiedCommand);
    if (command !== copiedCommand) return;
    copyState = 'copied';
  } catch {
    if (command !== copiedCommand) return;
    copyState = 'error';
  }
  resetTimer = setTimeout(() => (copyState = 'idle'), 4000);
}

onDestroy(() => clearTimeout(resetTimer));
</script>

<div class="install-commands" class:compact>
  {#if !compact}
    <div class="install-methods" role="group" aria-label="Installation method">
      <button
        type="button"
        class:chosen={method === 'app'}
        aria-pressed={method === 'app'}
        onclick={() => selectMethod('app')}
      >
        <AppWindow size={20} />
        <span>macOS app<small>Find app downloads</small></span>
      </button>
      <button
        type="button"
        class:chosen={method === 'script'}
        aria-pressed={method === 'script'}
        onclick={() => selectMethod('script')}
      >
        <Terminal size={20} />
        <span>Terminal<small>Guided installer</small></span>
      </button>
      <button
        type="button"
        class:chosen={method === 'brew'}
        aria-pressed={method === 'brew'}
        onclick={() => selectMethod('brew')}
      >
        <Package size={20} />
        <span>Homebrew<small>Build from source</small></span>
      </button>
      <button
        type="button"
        class:chosen={method === 'nix'}
        aria-pressed={method === 'nix'}
        onclick={() => selectMethod('nix')}
      >
        <Code size={20} /><span>Nix<small>Install the CLI</small></span>
      </button>
    </div>
  {/if}
  <div class="install-method-content">
    {#if method === 'app' || compact}
      <div class="app-install-content">
        <div>
          {#if !compact}
            <h3>Install the macOS app</h3>
          {/if}
          <p>Unzip the download and drag Pared to Applications.</p>
        </div>
        <a class="button button-primary" href={appDownload}
          ><Download size={17} />
          Download for macOS</a
        >
      </div>
    {/if}
    {#if method !== 'app' || compact}
      <div class="command-toolbar">
        <span class="command-language"
          >{compact ? 'Or install from Terminal' : method === 'script' ? 'Guided installer' : method === 'brew' ? 'Homebrew / CLI' : 'Nix / CLI'}</span
        >
        <button
          class="copy-command"
          type="button"
          onclick={copyCommand}
          aria-label="Copy installation command"
        >
          {#if copyState === 'copied'}
            <Check size={15} />
          {:else}
            <Copy size={15} />
          {/if}
          {copyState === 'copied' ? 'Copied' : 'Copy'}
        </button>
      </div>
      <button
        type="button"
        class="install-code"
        class:copy-failed={copyState === 'error'}
        onclick={copyCommand}
        aria-label="Copy command text"
        title="Click to copy"
      >
        <code>{command}</code>
      </button>
      <p class="command-note">
        {#if compact}
          Open Terminal, paste the command, and press Return.
        {:else if method === 'script'}
          Open Terminal, paste the command, and press Return. The wizard guides
          you through setup; no Xcode or Homebrew needed.
        {:else if method === 'brew'}
          Requires Xcode 27 or newer. Then run <code>pared wizard</code>.
        {:else}
          Requires Nix with flakes enabled.
        {/if}
      </p>
    {/if}
    {#if compact || method === 'app' || method === 'script'}
      <p class="command-note release-note">
        Downloads are available with the
        <a href={releasesPage}>first prebuilt release</a>.
      </p>
    {/if}
    {#if compact}
      <a
        class="nix-module-link"
        href={`${import.meta.env.BASE_URL}docs/#getting-started`}
        >More install options</a
      >
    {/if}
    {#if method === 'nix'}
      <a
        class="nix-module-link"
        href={`${import.meta.env.BASE_URL}docs/#quick-start`}
        >Configure with nix-darwin or Home Manager</a
      >
    {/if}
    <p
      class="copy-status"
      class:sr-only={copyState !== 'error'}
      role="status"
      aria-live="polite"
    >
      {#if copyState === 'error'}
        Couldn’t copy automatically. Select the command above to copy it
        manually.
      {:else if copyState === 'copied'}
        Installation command copied to clipboard.
      {/if}
    </p>
  </div>
</div>
