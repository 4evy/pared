export const installCommand =
  "curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/4evy/pared/releases/latest/download/install.sh | sh";

export const homebrewCommand = `brew tap 4evy/pared https://github.com/4evy/pared.git
brew install 4evy/pared/pared`;

export const appDownload =
  'https://github.com/4evy/pared/releases/latest/download/pared-app-macos-arm64.zip';

export const releasesPage = 'https://github.com/4evy/pared/releases';

export const nixCommand = `nix profile install github:4evy/pared
pared wizard`;
