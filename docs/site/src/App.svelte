<script lang="ts">
import { ModeWatcher } from 'mode-watcher';
import ModeToggle from './components/ModeToggle.svelte';
import OptionsReference from './components/OptionsReference.svelte';
import TitlePage from './components/TitlePage.svelte';
import { revision } from './content';

const example = `{
  imports = [ inputs.pared.darwinModules.default ];
  # For Home Manager, use inputs.pared.homeManagerModules.default instead

  programs.pared = {
    enable = true;
    defaultState = false;
    features.writingTools = true;
    features.spatialPhotos = null;
  };
}`;
</script>

<ModeWatcher
  defaultMode="system"
  themeColors={{ light: '#f5f5f5', dark: '#0f1318' }}
/>
<div
  class="min-h-screen bg-neutral-100 text-neutral-950 dark:bg-[#0f1318] dark:text-neutral-100"
>
  <main
    id="content"
    class="book relative mx-auto min-h-screen max-w-[62rem] border-x border-neutral-300 bg-white px-5 py-8 text-[16px] shadow-lg sm:px-10 lg:px-16 max-sm:border-x-0 max-sm:px-4 dark:border-neutral-800 dark:bg-[#12171d]"
  >
    <div class="flex items-start justify-between gap-4">
      <TitlePage title="Pared options" subtitle={`Revision ${revision}`} />
      <ModeToggle />
    </div>
    <section aria-labelledby="usage">
      <h2 id="usage" class="text-xl font-semibold">Quick start</h2>
      <p class="my-3">
        Add Pared as a flake input, import one of its modules, and configure
        <code>programs.pared</code>:
      </p>
      <pre
        class="my-4 overflow-x-auto rounded-md border border-neutral-200 bg-neutral-50 p-4 text-sm dark:border-neutral-700 dark:bg-[#171d24]"
      ><code>inputs.pared.url = "github:4evy/pared";</code></pre>
      <pre
        class="my-4 overflow-x-auto rounded-md border border-neutral-200 bg-neutral-50 p-4 text-sm dark:border-neutral-700 dark:bg-[#171d24]"
      ><code>{example}</code></pre>
      <p class="my-3">
        <code>true</code>
        enables a feature, <code>false</code> disables it, and
        <code>null</code>
        leaves it unmanaged. Unspecified features inherit
        <code>defaultState</code>. Unmanaged does not undo earlier preferences.
      </p>
      <p class="my-3">
        Rebuild your nix-darwin or Home Manager configuration to apply changes.
        For nix-darwin, set <code>system.primaryUser</code>. Generated profiles
        still need installation through System Settings or MDM. The installed
        profile blocks new model downloads for disabled features. Run
        <code>pared models cleanup</code>
        once to remove existing models; no cleanup job is scheduled.
      </p>
    </section>
    <OptionsReference />
    <footer
      class="mt-10 border-t border-neutral-300 pt-5 text-sm dark:border-neutral-700"
    >
      <a href="https://github.com/4evy/pared">Source on GitHub</a>
      · Site adapted from
      <a href="https://github.com/4evy/nixcord">Nixcord</a>
      (<a href="./LICENSE">MIT license</a>)
    </footer>
  </main>
</div>
