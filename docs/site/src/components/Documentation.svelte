<script lang="ts">
import { revision } from '../content';
import ManualNav from './ManualNav.svelte';
import OptionsReference from './OptionsReference.svelte';
import InstallCommands from './InstallCommands.svelte';

const base = import.meta.env.BASE_URL;

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
    content="Set up Pared, choose Apple Intelligence features, and remove downloaded models. Includes app instructions, the terminal wizard, and Nix configuration."
  >
</svelte:head>

<div class="docs-shell">
  <a class="skip-link" href="#content">Skip to main content</a>
  <ManualNav />
  <main id="content" class="book docs-content">
    <header class="docs-intro">
      <p class="eyebrow">Pared / The manual</p>
      <h1>Set up Pared.<br><em>Choose what stays.</em></h1>
      <p class="intro-description">
        Choose your features, install the matching profile, then remove models
        you no longer need. Use the app, terminal wizard, or Nix configuration.
      </p>
      <div class="intro-footer">
        <nav class="intro-links" aria-label="Quick links">
          <a href="#getting-started">Get started</a>
          <a href="#sec-options">Search Nix options</a>
        </nav>
        <p class="revision">
          Revision
          <a href={`https://github.com/4evy/pared/commit/${revision}`}
            ><code>{revision.slice(0, 8)}</code></a
          >
        </p>
      </div>
    </header>
    <section
      id="getting-started"
      class="guide-section"
      aria-labelledby="getting-started-title"
    >
      <p class="eyebrow">01 / Get Pared</p>
      <h2 id="getting-started-title">Getting started</h2>
      <p class="my-3">
        You’ll need an Apple silicon Mac (M1 or newer) running macOS 27 or
        newer. Opening Pared does not change your settings.
      </p>
      <InstallCommands initialMethod="app" />
      <p class="my-3">
        For source builds, see the
        <a
          class="guide-link"
          href="https://github.com/4evy/pared#build-from-source"
          >source build instructions</a
        >. The command-line guide covers
        <a
          class="guide-link"
          href="https://github.com/4evy/pared/blob/master/docs/cli.md#install"
          >other installation methods and offline setup</a
        >.
      </p>
      <h3 class="guide-subheading">Using the terminal wizard</h3>
      <p class="my-3">
        The installer opens the wizard. Choose <strong>Guided setup</strong>
        for a walkthrough, or run <code>pared wizard</code> to return later.
      </p>
      <p class="my-3">
        Use arrow keys and Enter to navigate, Space to select features, and
        <code>/</code>
        to search. Changes stay in a draft until you save; completed actions are
        kept if you skip steps.
      </p>
    </section>
    <section
      id="feature-choices"
      class="guide-section"
      aria-labelledby="feature-choices-title"
    >
      <p class="eyebrow">02 / Your choices</p>
      <h2 id="feature-choices-title">Choose features and finish setup</h2>
      <p class="my-3">
        Open <strong>Features</strong> in the app and choose each feature’s
        setting. These choices form a <em>policy</em>. A new policy starts with
        everything off; review it before saving.
      </p>
      <ul class="my-3 list-disc pl-6">
        <li>
          <strong>On</strong>
          permits the feature and keeps its models without downloading missing
          ones.
        </li>
        <li>
          <strong>Off</strong>
          disables supported controls. Models can be removed when every known
          feature sharing them is off.
        </li>
        <li>
          <strong>App Default</strong>
          removes local overrides without restoring older values. Apple supplies
          defaults where no other policy applies.
        </li>
      </ul>
      <p class="my-3">
        Save, open <strong>Setup</strong>, and install the profile in System
        Settings. It applies supported controls and blocks unwanted downloads.
        Replace it after every change, including App Default; its settings stay
        in effect until replaced or removed.
      </p>
      <p class="my-3">
        Some restrictions require supervised mobile device management (MDM).
        Installing a profile does not guarantee every control works; see the
        <a
          class="guide-link"
          href="https://github.com/4evy/pared/blob/master/docs/how-it-works.md#profile-compatibility"
          >profile compatibility notes</a
        >.
      </p>
    </section>
    <section
      id="model-cleanup"
      class="guide-section"
      aria-labelledby="model-cleanup-title"
    >
      <p class="eyebrow">03 / Downloaded models</p>
      <h2 id="model-cleanup-title">Remove models you no longer need</h2>
      <p class="my-3">
        After installing the matching profile, open <strong>Overview</strong>
        or <strong>Models</strong> to review and confirm removal. Saving feature
        choices alone does not remove models.
      </p>
      <p class="my-3">
        Shared models stay while any known feature needs them, including Siri’s
        foundation models. Apple’s asset service handles removal, so System
        Integrity Protection (SIP) stays enabled.
      </p>
      <h3 class="guide-subheading">If models stay after removal</h3>
      <p class="my-3">
        Close affected apps, log out or restart, then check
        <code>pared models status</code>
        before retrying. After a timeout, check status first: removal may
        already have happened.
      </p>
      <p class="my-3">
        Pared checks folders, not recovered disk space; macOS may update its
        storage total later. Keep the profile installed to block new downloads.
      </p>
      <h3 class="guide-subheading">To use a feature again</h3>
      <p class="my-3">
        Turn the feature on, save, and install the updated profile. Then request
        its models from <strong>Overview</strong> or <strong>Models</strong>.
        Downloads run in the background; acceptance does not confirm completion.
        For features Pared cannot download directly, turn them on in their Apple
        app.
      </p>
    </section>
    <section
      id="command-line"
      class="guide-section"
      aria-labelledby="command-line-title"
    >
      <p class="eyebrow">04 / Command line</p>
      <h2 id="command-line-title">Use the CLI directly</h2>
      <p class="my-3">
        List feature names, inspect settings, and preview removal:
      </p>
      <pre class="guide-code"><code>pared features
pared status
pared models cleanup --dry-run</code></pre>
      <p class="my-3">
        The default policy is
        <code>~/Library/Application Support/pared/policy.json</code>. Use
        <code>--policy FILE</code>
        to read another policy, including one generated by Nix.
      </p>
      <p class="my-3">
        Read the
        <a
          class="guide-link"
          href="https://github.com/4evy/pared/blob/master/docs/cli.md"
          >command-line guide</a
        >
        for feature changes and model removal. Run <code>pared --help</code>
        for all commands.
      </p>
    </section>
    <section
      id="quick-start"
      class="guide-section"
      aria-labelledby="quick-start-title"
    >
      <p class="eyebrow">05 / Nix</p>
      <h2 id="quick-start-title">Keep your choices in Nix</h2>
      <p class="my-3">
        Pared includes nix-darwin and Home Manager modules. Add it to your flake
        inputs:
      </p>
      <pre
        class="guide-code my-4"
      ><code>inputs.pared.url = "github:4evy/pared";</code></pre>
      <p class="my-3">
        Pass <code>inputs</code> through <code>specialArgs</code> (nix-darwin)
        or <code>extraSpecialArgs</code> (Home Manager), then configure the
        module:
      </p>
      <pre class="guide-code my-4"><code>{example}</code></pre>
      <p class="my-3">
        Use <code>true</code> for on, <code>false</code> for off, and
        <code>null</code>
        for unmanaged. Unlisted features inherit
        <code>defaultState</code>
        (default: <code>false</code>), so this example disables everything
        except Writing Tools and Spatial Photos. Setting
        <code>null</code>
        stops writing preferences but leaves earlier values in place.
      </p>
      <h3 class="guide-subheading">Rebuild and install the profile</h3>
      <p class="my-3">
        Set <code>system.primaryUser</code> for nix-darwin user preferences,
        then rebuild to apply preferences and generate the profile. Install
        <code>disable-apple-intelligence.mobileconfig</code>
        through System Settings from <code>/etc/pared</code> (nix-darwin) or
        <code>$XDG_CONFIG_HOME/pared</code>
        (Home Manager, usually <code>~/.config/pared</code>). Rebuilding does
        not install or replace the profile.
      </p>
      <p class="my-3">
        The same directory contains <code>policy.json</code> and
        <code>declarations.json</code>. The declarations are for supervised MDM
        enrollment; System Settings cannot install them.
      </p>
      <h3 class="guide-subheading">Model cleanup during activation</h3>
      <p class="my-3">
        Both modules remove eligible models during activation by default.
        Activation does not wait for profile installation. Set
        <code>programs.pared.cleanupOnActivation = false;</code>
        to opt out. Keep the matching profile installed to block future
        downloads.
      </p>
      <p class="my-3">
        Activation skips cleanup when the policy matches the last successful
        cleanup. A changed policy or failed cleanup triggers another attempt.
      </p>
      <p class="my-3">
        The CLI uses a separate policy by default. Inspect the nix-darwin policy
        with <code>pared status --policy /etc/pared/policy.json</code>; for Home
        Manager, use its configuration directory. Change Nix-managed settings in
        Nix, then rebuild and replace the installed profile. Policies in
        <code>/nix/store</code>
        are read-only in the app and CLI.
      </p>
      <a class="guide-link" href={`${base}#how-it-works`}
        >Back to the product overview</a
      >
    </section>
    <OptionsReference />
  </main>
</div>
