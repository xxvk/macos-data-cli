import { languages } from './build-context.mjs';

const brand = {
  'en-US': { title: 'mpia', tagline: 'macOS personal intelligent access for AI agents' },
  'zh-CN': { title: 'mpia', tagline: '面向 AI Agent 的 macOS 个人智能访问' },
  'ja-JP': { title: 'mpia', tagline: 'AI エージェント向け macOS パーソナルインテリジェントアクセス' },
};

const shellUi = {
  'en-US': { search: 'Search commands' },
  'zh-CN': { search: '搜索命令' },
  'ja-JP': { search: 'コマンドを検索' },
};

function languageLinks(language, languageHref) {
  return languages
    .map(({ code, label }) => `<a href="${languageHref(code)}"${code === language ? ' aria-current="page"' : ''}>${label}</a>`)
    .join('');
}

function topbar(language, languageHref) {
  const ui = shellUi[language];
  const b = brand[language];
  return `<header class="mpia-topbar">
    <a class="mpia-brand" href="${languageHref(language)}"><span class="mpia-brand-title">${b.title}</span><span class="mpia-brand-tagline">${b.tagline}</span></a>
    <div class="mpia-topbar-actions">
      <a class="mpia-github-link" href="https://github.com/xxvk/mpia-cli" target="_blank" rel="noopener noreferrer" aria-label="GitHub"><svg viewBox="0 0 16 16" width="20" height="20" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"></path></svg></a>
      <button class="mpia-mobile-search" type="button" aria-label="${ui.search}"><svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M229.66,218.34l-50.07-50.06a88.11,88.11,0,1,0-11.31,11.31l50.06,50.07a8,8,0,0,0,11.32-11.32ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z"></path></svg></button>
    </div>
  </header>`;
}

function serialize(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

export function referencePage({ language, spec, assetPrefix = '../assets', rootPrefix = '../', languageHref }) {
  const b = brand[language];
  const config = {
    content: spec,
    theme: 'alternate',
    hideClientButton: true,
    hideTestRequestButton: false,
    hiddenClients: true,
    telemetry: false,
    agent: { disabled: true },
    localization: {
      locale: languages.find((item) => item.code === language).scalarLocale,
    },
  };
  return `<!doctype html>
<html lang="${language}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>${b.title} · ${b.tagline}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:ital,wght@0,700;1,700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="${assetPrefix}/scalar-shell.css">
</head>
<body data-mpia-root-prefix="${rootPrefix}">
  ${topbar(language, languageHref)}
  <template id="mpia-language-switcher-template"><nav class="language-switcher" aria-label="Documentation language"><span class="language-tabs">${languageLinks(language, languageHref)}</span></nav></template>
  <script id="api-reference" type="application/json" data-configuration="${serialize(config).replace(/"/g, '&quot;')}"></script>
  <script src="${assetPrefix}/scalar.js"></script>
  <script src="${assetPrefix}/scalar-shell.js"></script>
</body>
</html>`;
}
