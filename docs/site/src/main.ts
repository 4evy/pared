import './styles.css';
import './landing.css';
import { mount } from 'svelte';
import App from './App.svelte';

document.documentElement.classList.add('scroll-smooth');
document.body.classList.add(
  'm-0',
  'min-h-screen',
  'font-sans',
  'antialiased',
  'leading-[1.55]',
  '[text-rendering:optimizeLegibility]',
);

const target = document.getElementById('app');
if (!target) throw new Error('Missing app mount element');

const page = document.body.dataset.page === 'docs' ? 'docs' : 'home';

function redirectLegacyDocs() {
  if (
    /^#opt-/.test(window.location.hash) ||
    ['#sec-options', '#quick-start'].includes(window.location.hash) ||
    new URLSearchParams(window.location.search).has('q')
  ) {
    window.location.replace(
      `${import.meta.env.BASE_URL}docs/${window.location.search}${window.location.hash}`,
    );
    return true;
  }
  return false;
}

if (page === 'home') {
  window.addEventListener('hashchange', redirectLegacyDocs);
}

if (page === 'docs' || !redirectLegacyDocs()) {
  mount(App, { target, props: { page } });
}
