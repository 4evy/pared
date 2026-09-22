import type { OptionEntry, RawOption } from './types';
export function stringifyDocValue(value: unknown): string {
  if (value == null) return 'Not specified';
  if (typeof value === 'string') return value;
  if (
    typeof value === 'object' &&
    'text' in value &&
    typeof value.text === 'string'
  )
    return value.text;
  return JSON.stringify(value, null, 2);
}
export async function loadOptions(): Promise<OptionEntry[]> {
  const response = await fetch(`${import.meta.env.BASE_URL}options.json`);
  if (!response.ok)
    throw new Error(`Could not load options.json (${response.status})`);
  const raw = (await response.json()) as Record<string, RawOption>;
  return Object.entries(raw)
    .map(([name, option]) => ({
      ...option,
      name,
      searchText:
        `${name} ${option.type ?? ''} ${stringifyDocValue(option.description)}`.toLowerCase(),
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
