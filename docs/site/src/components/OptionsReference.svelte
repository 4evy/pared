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
  <TitlePage id="sec-options" title="Option reference" level={2} />
  {#if error}
    <p role="alert">{error}</p>
    <button type="button" class={focusClass} onclick={() => void load()}>
      Retry
    </button>
  {:else if loading}
    <p role="status">Loading configuration options…</p>
  {:else}
    <search class="options-toolbar" aria-label="Configuration options">
      <label class="search-label" for="option-search"
        >Search configuration options</label
      >
      <div class="option-search-field">
        <span class="search-icon" aria-hidden="true">⌕</span>
        <input
          id="option-search"
          type="search"
          bind:value={query}
          placeholder="Name, description, or type"
          autocomplete="off"
        >
        {#if query}
          <button
            type="button"
            class="clear-search"
            aria-label="Clear option search"
            title="Clear search"
            onclick={() => (query = '')}
          >
            ×
          </button>
        {/if}
      </div>
    </search>
    <div class="option-actions">
      <p role="status" aria-live="polite">
        {query.trim()
          ? `${matches.length} of ${options.length} options match your search`
          : `${options.length} options available`}
      </p>
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
