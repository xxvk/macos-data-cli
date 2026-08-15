import { languages } from './build-context.mjs';

const brand = {
  'en-US': { title: 'mpia', tagline: 'macOS data access for agents' },
  'zh-CN': { title: 'mpia', tagline: '面向 agent 的 macOS 数据访问层' },
  'ja-JP': { title: 'mpia', tagline: 'エージェント向け macOS データアクセス' },
};

const shellUi = {
  'en-US': { search: 'Search commands', overview: 'Overview', reference: 'Command reference', version: 'Version' },
  'zh-CN': { search: '搜索命令', overview: '概览', reference: '命令参考', version: '版本' },
  'ja-JP': { search: 'コマンドを検索', overview: '概要', reference: 'コマンドリファレンス', version: 'バージョン' },
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
    <nav class="mpia-language-switcher" aria-label="Documentation language"><span class="mpia-language-tabs">${languageLinks(language, languageHref)}</span></nav>
    <button class="mpia-mobile-search" type="button" aria-label="${ui.search}"><svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M229.66,218.34l-50.07-50.06a88.11,88.11,0,1,0-11.31,11.31l50.06,50.07a8,8,0,0,0,11.32-11.32ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z"></path></svg></button>
  </header>`;
}

function serialize(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

export function referencePage({ language, spec, assetPrefix = '../assets', rootPrefix = '../', overviewHref, languageHref }) {
  const ui = shellUi[language];
  const b = brand[language];
  const config = {
    content: spec,
    theme: 'alternate',
    hideClientButton: true,
    hideTestRequestButton: true,
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
  <title>${b.title} · ${ui.reference}</title>
  <link rel="stylesheet" href="${assetPrefix}/scalar-shell.css">
</head>
<body data-mpia-root-prefix="${rootPrefix}" data-mpia-overview-href="${overviewHref}">
  ${topbar(language, languageHref)}
  <template id="mpia-language-switcher-template"><nav class="language-switcher" aria-label="Documentation language"><span class="language-tabs">${languageLinks(language, languageHref)}</span></nav></template>
  <script id="api-reference" type="application/json" data-configuration="${serialize(config).replace(/"/g, '&quot;')}"></script>
  <script src="${assetPrefix}/scalar.js"></script>
  <script src="${assetPrefix}/scalar-shell.js"></script>
</body>
</html>`;
}

export function landingPage({ language, bodyHtml, assetPrefix = '../assets', rootPrefix = '../', referenceHref, languageHref }) {
  const ui = shellUi[language];
  const b = brand[language];
  return `<!doctype html>
<html lang="${language}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>${b.title} · ${ui.overview}</title>
  <link rel="stylesheet" href="${assetPrefix}/scalar-shell.css">
</head>
<body data-mpia-root-prefix="${rootPrefix}">
  ${topbar(language, languageHref)}
  <main class="mpia-landing">
    <h1>${b.title}</h1>
    <p class="mpia-landing-tagline">${b.tagline}</p>
    <nav class="mpia-landing-nav"><a class="mpia-landing-cta" href="${referenceHref}">${ui.reference} →</a></nav>
    <div class="mpia-landing-body">${bodyHtml}</div>
  </main>
</body>
</html>`;
}
