<script lang="ts">
import BookOpen from '@lucide/svelte/icons/book-open';
import ChevronDown from '@lucide/svelte/icons/chevron-down';
import ClipboardCheck from '@lucide/svelte/icons/clipboard-check';
import Layers from '@lucide/svelte/icons/layers';
import ShieldCheck from '@lucide/svelte/icons/shield-check';
import Terminal from '@lucide/svelte/icons/terminal';
import X from '@lucide/svelte/icons/x';
import ZoomIn from '@lucide/svelte/icons/zoom-in';
import { siGithub } from 'simple-icons';
import BrandIcon from './BrandIcon.svelte';
import InstallCommands from './InstallCommands.svelte';
import ModeToggle from './ModeToggle.svelte';

const base = import.meta.env.BASE_URL;
const docs = `${base}docs/`;
const screenshotNames = ['overview', 'features', 'setup'] as const;
let screen = $state<(typeof screenshotNames)[number]>('overview');
let screenshotDialog: HTMLDialogElement;
const screenshots = {
  overview: {
    title: 'Overview',
    image: 'app-overview.webp',
    width: 1232,
    height: 872,
    alt: 'Pared Overview with a choice summary, feature controls, model removal, and expandable downloads',
    caption: 'Start with feature choices. Manage models separately.',
  },
  features: {
    title: 'Features',
    image: 'app-features.webp',
    width: 1232,
    height: 872,
    alt: 'Pared Features view with Writing Tools set to Off in the draft choices',
    caption: 'Choose On, Off, or App Default for each feature.',
  },
  setup: {
    title: 'Setup',
    image: 'app-setup.webp',
    width: 1232,
    height: 872,
    alt: 'Pared Setup view with profile installation status and three steps to finish setup',
    caption: 'Save your choices, then install the profile in System Settings.',
  },
};
const selected = $derived(screenshots[screen]);
const steps = [
  {
    number: '01',
    title: 'Choose your features',
    text: 'Keep the features you use, turn off the rest, or let each app use its defaults.',
  },
  {
    number: '02',
    title: 'Finish setup',
    text: 'Approve Pared’s configuration profile in System Settings to apply supported controls and block unwanted model downloads.',
  },
  {
    number: '03',
    title: 'Review model removal',
    text: 'See which models can go, then confirm removal. Pared keeps shared models needed by features in its catalog that you leave on.',
  },
];
</script>

<svelte:head>
  <title>Pared — A little less AI. A little more Mac.</title>
  <meta
    name="description"
    content="Choose which Apple Intelligence features stay on your Mac, and remove the downloaded models you no longer need. Free, open source, and built for macOS."
  >
</svelte:head>

<div class="landing">
  <a class="skip-link" href="#content">Skip to main content</a>
  <header class="site-header">
    <a class="site-brand" href={base} aria-label="Pared home"
      ><BrandIcon />pared</a
    >
    <nav class="site-nav" aria-label="Main navigation">
      <a href={docs}>Docs</a>
      <a class="nav-install" href="#install">Get Pared</a>
      <div class="site-nav-controls">
        <a
          class="icon-button"
          href="https://github.com/4evy/pared"
          aria-label="GitHub repository"
          title="GitHub repository"
          ><span class="sr-only">GitHub repository</span
          ><svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d={siGithub.path} />
          </svg></a
        >
        <ModeToggle />
      </div>
    </nav>
  </header>

  <main id="content">
    <section class="hero" aria-labelledby="hero-title">
      <div class="hero-copy">
        <p class="eyebrow">Your Mac. Your call.</p>
        <h1 id="hero-title">
          A little less AI.<br>
          <em>A little more Mac.</em>
        </h1>
        <p class="hero-description">
          Choose the Apple Intelligence features you want. Turn off the rest and
          remove the downloaded models you no longer need.
        </p>
        <p class="hero-license">
          Apple silicon · macOS 27+ · Free & open source
        </p>
        <section id="install" class="hero-install" aria-label="Get Pared">
          <InstallCommands compact initialMethod="app" />
        </section>
      </div>
      <figure class="app-showcase">
        <div class="showcase-toolbar">
          <span class="figure-label">01 / The macOS app</span>
          <fieldset class="screenshot-switch" aria-label="App screenshots">
            {#each screenshotNames as name}
              <button
                type="button"
                class:chosen={screen === name}
                aria-pressed={screen === name}
                onclick={() => (screen = name)}
              >
                {screenshots[name].title}
              </button>
            {/each}
          </fieldset>
        </div>
        <div class="screenshot-mat">
          <button
            type="button"
            class="enlarge-screenshot"
            onclick={() => screenshotDialog.showModal()}
            aria-label="View full-size app screenshot"
          >
            <img
              class="app-screenshot"
              src={`${base}images/${selected.image}`}
              width={selected.width}
              height={selected.height}
              fetchpriority="high"
              alt={selected.alt}
            >
          </button>
        </div>
        <figcaption>
          <span>{selected.caption}</span
          ><button
            type="button"
            onclick={() => screenshotDialog.showModal()}
            aria-label="Enlarge app screenshot"
          >
            <ZoomIn size={18} />
          </button>
        </figcaption>
      </figure>
    </section>

    <section class="principles" aria-label="Project highlights">
      <p>
        <ShieldCheck size={17} aria-hidden="true" />
        Mac system protection stays on
      </p>
      <p>
        <ClipboardCheck size={17} aria-hidden="true" />
        Review before removing
      </p>
      <p>
        <Layers size={17} aria-hidden="true" />
        Keep models for features you use
      </p>
      <span class="principles-note">Less, on purpose.</span>
    </section>

    <section id="how-it-works" class="how-section" aria-labelledby="how-title">
      <div class="section-copy">
        <p class="eyebrow">How it works</p>
        <h2 id="how-title">Keep what’s useful.<br><em>Let the rest go.</em></h2>
        <a class="text-link" href={`${docs}#model-cleanup`}
          ><BookOpen size={16} />
          What removal does</a
        >
      </div>
      <ol class="steps">
        {#each steps as step (step.number)}
          <li>
            <span class="step-number" aria-hidden="true">{step.number}</span>
            <div>
              <h3>{step.title}</h3>
              <p>{step.text}</p>
            </div>
          </li>
        {/each}
      </ol>
    </section>

    <section id="wizard" class="wizard-section" aria-labelledby="wizard-title">
      <div class="wizard-inner">
        <div class="wizard-heading">
          <p class="eyebrow">02 / The terminal wizard</p>
          <span class="terminal-label">$ pared wizard</span>
        </div>
        <div class="wizard-layout">
          <div class="wizard-copy">
            <h2 id="wizard-title">More of a<br><em>terminal person?</em></h2>
            <p>
              The wizard walks you through feature choices, profile setup, and
              model removal. Review your changes before saving.
            </p>
            <a class="text-link" href="#install"
              ><Terminal size={17} />
              Get the CLI</a
            >
            <dl class="keyboard-guide">
              <div>
                <dt><kbd>Up</kbd> <kbd>Down</kbd></dt>
                <dd>Move around</dd>
              </div>
              <div>
                <dt><kbd>Space</kbd></dt>
                <dd>Select a feature</dd>
              </div>
              <div>
                <dt><kbd>/</kbd></dt>
                <dd>Find what you need</dd>
              </div>
            </dl>
          </div>
          <figure class="wizard-showcase">
            <video
              controls
              preload="none"
              poster={`${base}images/wizard.webp`}
              width="1080"
              height="780"
              aria-label="Pared terminal wizard walkthrough: select features, review and discard changes, and decline model removal"
            >
              <source src={`${base}images/wizard.webm`} type="video/webm">
              <track
                kind="captions"
                src={`${base}images/wizard.vtt`}
                srclang="en"
                label="English"
                default
              >
              <a href={`${base}images/wizard.webp`}
                >View the wizard screenshot</a
              >
            </video>
            <figcaption>
              Selecting features and reviewing changes in the wizard.
            </figcaption>
          </figure>
        </div>
      </div>
    </section>

    <section class="faq-section" aria-labelledby="faq-title">
      <div class="section-copy">
        <p class="eyebrow">Before you start</p>
        <h2 id="faq-title">A few questions,<br><em>answered.</em></h2>
        <a class="text-link" href={docs}
          ><BookOpen size={16} />
          Read the manual</a
        >
      </div>
      <div class="faq-list">
        <details>
          <summary>
            Do I need to disable my Mac’s system protection?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            System Integrity Protection (SIP) stays enabled. Pared asks Apple’s
            own asset service to remove models using the permissions it already
            has.
          </p>
        </details>
        <details>
          <summary>
            Does saving settings remove models?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            Saving applies feature settings. Removing models is a separate
            action, with its own review and confirmation in the app and wizard.
          </p>
        </details>
        <details>
          <summary>
            Can I keep Siri or other features?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            Yes. Leave a feature on, or choose App Default to let its app
            control it. Pared keeps models used by those features in its
            catalog. Keeping Siri also keeps its shared foundation models.
          </p>
        </details>
        <details>
          <summary>
            How much storage will I get back?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            It depends on which models are downloaded and which features you
            keep. Pared checks whether model folders remain after removal; it
            does not measure recovered disk space. macOS may update its storage
            total later.
          </p>
        </details>
        <details>
          <summary>
            Why might some models stay?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            macOS can keep models that are in use. Close affected apps, log out
            or restart, then check model status before retrying.
          </p>
        </details>
        <details>
          <summary>
            Does every feature switch work on a personal Mac?<ChevronDown
              size={18}
              aria-hidden="true"
            />
          </summary>
          <p>
            Some feature restrictions require a Mac enrolled in device
            management. On a personal Mac, Pared applies the local settings and
            profile controls macOS supports. Its profile also blocks downloads
            for model groups whose known features are all off.
          </p>
        </details>
      </div>
    </section>
  </main>

  <footer class="site-footer">
    <a class="site-brand" href={base} aria-label="Pared home">pared</a>
    <p>A little less, a little more yours.</p>
    <nav aria-label="Footer navigation">
      <a href={docs}>Documentation</a
      ><a href="https://github.com/4evy/pared">Source</a
      ><a href={`${base}LICENSE`}>MIT license</a>
    </nav>
  </footer>
  <dialog
    bind:this={screenshotDialog}
    class="screenshot-dialog"
    aria-label="Full-size Pared app screenshot"
  >
    <div class="dialog-toolbar">
      <span class="figure-label">Pared / {selected.title}</span>
      <button
        class="icon-button"
        type="button"
        aria-label="Close screenshot"
        onclick={() => screenshotDialog.close()}
      >
        <X size={20} />
      </button>
    </div>
    <img
      src={`${base}images/${selected.image}`}
      width={selected.width}
      height={selected.height}
      alt={selected.alt}
    >
  </dialog>
</div>
