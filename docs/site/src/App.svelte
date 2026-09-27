<script lang="ts">
import { ModeWatcher } from 'mode-watcher';
import ManualNav from './components/ManualNav.svelte';
import OptionsReference from './components/OptionsReference.svelte';
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

<svelte:head>
  <title>Pared documentation</title>
  <meta
    name="description"
    content="Configure Pared with nix-darwin or Home Manager and browse its options"
  >
</svelte:head>

<ModeWatcher
  defaultMode="system"
  themeColors={{ light: '#f5f5f5', dark: '#0f1318' }}
/>
<div class="docs-shell">
  <a class="skip-link" href="#content">Skip to main content</a>
  <ManualNav />
  <main id="content" class="book docs-content">
    <header class="docs-intro">
      <h1>Pared documentation</h1>
      <p class="intro-description">
        Manage Apple Intelligence features and model cleanup with nix-darwin or
        Home Manager.
      </p>
      <div class="intro-footer">
        <nav class="intro-links" aria-label="Quick links">
          <a href="#sec-options">Search options →</a>
          <a href="#quick-start">Get started →</a>
        </nav>
        <p class="revision">
          Revision
          <a href={`https://github.com/4evy/pared/commit/${revision}`}
            ><code>{revision.slice(0, 8)}</code></a
          >
        </p>
      </div>
    </header>
    <OptionsReference />
    <section
      id="quick-start"
      class="guide-section"
      aria-labelledby="quick-start-title"
    >
      <h2 id="quick-start-title">Quick start</h2>
      <p class="my-3">Add Pared to your flake inputs:</p>
      <pre
        class="my-4 overflow-x-auto rounded-md border border-neutral-200 bg-neutral-50 p-4 text-sm dark:border-neutral-700 dark:bg-[#171d24]"
      ><code>inputs.pared.url = "github:4evy/pared";</code></pre>
      <p class="my-3">
        Pass <code>inputs</code> through <code>specialArgs</code> (nix-darwin)
        or
        <code>extraSpecialArgs</code>
        (Home Manager), then configure the module:
      </p>
      <pre
        class="my-4 overflow-x-auto rounded-md border border-neutral-200 bg-neutral-50 p-4 text-sm dark:border-neutral-700 dark:bg-[#171d24]"
      ><code>{example}</code></pre>
      <p class="my-3">
        Unlisted features inherit <code>defaultState</code> (normally
        <code>false</code>). <code>true</code> enables a feature,
        <code>false</code>
        disables it, and <code>null</code> leaves it unmanaged.
        <code>null</code>
        does not remove earlier preferences.
      </p>
      <p class="my-3">
        Rebuild to apply preferences and generate the profile. For nix-darwin
        user preferences, set <code>system.primaryUser</code>. Install
        <code>disable-apple-intelligence.mobileconfig</code>
        through System Settings from <code>/etc/pared</code> (nix-darwin) or
        <code>$XDG_CONFIG_HOME/pared</code>
        (Home Manager, usually
        <code>~/.config/pared</code>). Rebuilding does not install it.
      </p>
      <p class="my-3">
        Activation removes models when all known consumers are disabled. Cleanup
        runs again if the policy changes or the previous run failed. Set
        <code>programs.pared.cleanupOnActivation = false;</code>
        to opt out. Install the profile to block future downloads.
      </p>
      <p class="my-3">
        The CLI uses a separate policy by default. Inspect the nix-darwin policy
        with <code>pared status --policy /etc/pared/policy.json</code>; for Home
        Manager, use its configuration directory. Change Nix-managed settings in
        Nix, then rebuild and replace the installed profile.
      </p>
    </section>
  </main>
</div>
