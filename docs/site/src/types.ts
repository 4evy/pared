export type RawOption = {
  declarations?: { name?: string; url?: string }[];
  default?: unknown;
  description?: unknown;
  example?: unknown;
  type?: string;
};
export type OptionEntry = RawOption & { name: string; searchText: string };
