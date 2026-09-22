<script lang="ts">
import { onMount, tick } from 'svelte';
import { focusClass, topSectionClass } from '../classes';
import { loadOptions } from '../options';
import type { OptionEntry } from '../types';
import OptionDefinition from './OptionDefinition.svelte';
import TitlePage from './TitlePage.svelte';

let options = $state<OptionEntry[]>([]);
let error = $state('');
let loading = $state(true);
let query = $state(new URLSearchParams(window.location.search).get('q') ?? '');
let opened = $state<Record<string, boolean>>({});
const matches = $derived(
  options.filter((option) =>
    option.searchText.includes(query.trim().toLowerCase()),
  ),
);
$effect(() => {
  const url = new URL(window.location.href);
  if (query) url.searchParams.set('q', query);
  else url.searchParams.delete('q');
  window.history.replaceState(window.history.state, '', url);
});
async function revealHash() {
  let name: string;
  try {
    name = decodeURIComponent(window.location.hash.slice(5));
  } catch {
    return;
  }
  if (!window.location.hash.startsWith('#opt-')) return;
  const option = options.find((option) => option.name === name);
  if (!option) return;
  if (!option.searchText.includes(query.trim().toLowerCase())) query = '';
  opened = { ...opened, [name]: true };
  await tick();
  document.getElementById(`opt-${name}`)?.scrollIntoView();
}
async function load() {
  loading = true;
  error = '';
  try {
    options = await loadOptions();
    await revealHash();
  } catch (cause) {
    error = cause instanceof Error ? cause.message : String(cause);
  } finally {
    loading = false;
    await tick();
    await revealHash();
  }
}
onMount(() => {
  void load();
  const onHash = () => void revealHash();
  const onPop = () => {
    query = new URLSearchParams(window.location.search).get('q') ?? '';
    void revealHash();
  };
  window.addEventListener('hashchange', onHash);
  window.addEventListener('popstate', onPop);
  return () => {
    window.removeEventListener('hashchange', onHash);
    window.removeEventListener('popstate', onPop);
  };
});
</script>
<section class={topSectionClass} aria-labelledby="sec-options">
  <TitlePage id="sec-options" title="Configuration options" level={2} />
  <p>
    Generated from Pared's shared Nix module and feature catalog. These options
    apply to both nix-darwin and Home Manager. Feature defaults inherit
    <code>programs.pared.defaultState</code>.
  </p>
  {#if error}
    <p role="alert">{error}</p>
    <button type="button" class={focusClass} onclick={() => void load()}>
      Retry
    </button>
  {:else if loading}
    <p role="status">Loading configuration options…</p>
  {:else}
    <label class="mt-5 block font-semibold" for="option-search"
      >Search options</label
    >
    <input
      id="option-search"
      type="search"
      bind:value={query}
      placeholder="Feature, option, or description"
      class={`my-2 w-full rounded-sm border border-neutral-400 p-3 dark:bg-[#171d24] ${focusClass}`}
    >
    <div class="flex flex-wrap items-center gap-4 text-sm">
      <p role="status">{matches.length} of {options.length} options</p>
      <button type="button" class={focusClass} onclick={() => (query = '')}>
        Clear search
      </button>
      <button
        type="button"
        class={focusClass}
        onclick={() =>
  (opened = Object.fromEntries(matches.map((option) => [option.name, true])))}
      >
        Expand results
      </button>
      <button type="button" class={focusClass} onclick={() => (opened = {})}>
        Collapse all
      </button>
    </div>
    {#if matches.length === 0}
      <p>No options match this search.</p>
    {/if}
    <h3 class="sr-only">Option definitions</h3>
    <ul class="m-0 list-none p-0">
      {#each matches as option (option.name)}
        <OptionDefinition
          {option}
          open={opened[option.name] ?? false}
          onToggle={(open) => (opened = { ...opened, [option.name]: open })}
        />
      {/each}
    </ul>
  {/if}
</section>
