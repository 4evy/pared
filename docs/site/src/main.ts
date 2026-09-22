import './styles.css';
import { mount } from 'svelte';
import App from './App.svelte';

document.documentElement.classList.add('scroll-smooth');
document.body.classList.add(
  'm-0',
  'min-h-screen',
  'bg-neutral-100',
  'dark:bg-[#0f1318]',
  'font-sans',
  'text-neutral-950',
  'dark:text-neutral-100',
  'antialiased',
  'leading-[1.55]',
  '[text-rendering:optimizeLegibility]',
);

const target = document.getElementById('app');
if (!target) throw new Error('Missing app mount element');

mount(App, { target });
