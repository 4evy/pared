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
        Add Pared to your flake inputs. Pass <code>inputs</code> through
        <code>specialArgs</code>
        for nix-darwin or <code>extraSpecialArgs</code>
        for Home Manager, then import the module and configure
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
        omits it from generated settings. Features you do not list inherit
        <code>defaultState</code>, which defaults to <code>false</code>. This
        example enables Writing Tools, leaves Spatial Photos unmanaged, and
        disables all other features. Changing a setting to
        <code>null</code>
        does not remove preferences written earlier.
      </p>
      <p class="my-3">
        Rebuild your configuration to apply the preferences and generate a
        profile. For nix-darwin, set <code>system.primaryUser</code> for user
        preferences. Install
        <code>disable-apple-intelligence.mobileconfig</code>
        through System Settings from <code>/etc/pared</code> (nix-darwin) or
        <code>$XDG_CONFIG_HOME/pared</code>
        (Home Manager, normally
        <code>~/.config/pared</code>). Rebuilding does not install the profile.
      </p>
      <p class="my-3">
        Both modules remove models during activation when all their known
        consumers are disabled. A successful cleanup is recorded and runs again
        only when the policy changes; a failed cleanup retries on the next
        activation. Set
        <code>programs.pared.cleanupOnActivation = false;</code> to opt out.
        Install the profile to block future downloads of those models.
      </p>
      <p class="my-3">
        CLI commands use a separate policy by default. To inspect the nix-darwin
        policy, run
        <code>pared status --policy /etc/pared/policy.json</code>. For Home
        Manager, use the policy in its configuration directory. Change
        Nix-managed settings in Nix and rebuild, then replace the installed
        profile.
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
