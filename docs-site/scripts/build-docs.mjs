import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { marked } from 'marked';
import { dist, docsSiteRoot, languages, openApiPath } from './build-context.mjs';
import { localizeOpenApiSpec } from './localize.mjs';
import { landingPage, referencePage } from './scalar-page.mjs';

rmSync(dist, { recursive: true, force: true });
mkdirSync(resolve(dist, 'assets'), { recursive: true });

for (const asset of ['scalar-shell.css', 'scalar-shell.js']) {
  cpSync(resolve(docsSiteRoot, 'site', asset), resolve(dist, 'assets', asset));
}
cpSync(
  resolve(docsSiteRoot, 'node_modules/@scalar/api-reference/dist/browser/standalone.js'),
  resolve(dist, 'assets/scalar.js'),
);

const sourceSpec = JSON.parse(readFileSync(openApiPath, 'utf8'));
if (sourceSpec.openapi !== '3.1.0') {
  throw new Error('docs/openapi.json is not OpenAPI 3.1.0. Run scripts/generate_openapi.py locally first.');
}

for (const { code } of languages) {
  const localized = localizeOpenApiSpec(sourceSpec, code);
  const overviewMarkdown = readFileSync(resolve(docsSiteRoot, 'guides', code, 'overview.md'), 'utf8');
  const bodyHtml = marked.parse(overviewMarkdown);

  mkdirSync(resolve(dist, code), { recursive: true });
  writeFileSync(resolve(dist, code, 'index.html'), landingPage({
    language: code,
    bodyHtml,
    assetPrefix: '../assets',
    rootPrefix: '../',
    referenceHref: `../reference/${code}/index.html`,
    languageHref: (target) => `../${target}/index.html`,
  }));

  mkdirSync(resolve(dist, 'reference', code), { recursive: true });
  writeFileSync(resolve(dist, 'reference', code, 'index.html'), referencePage({
    language: code,
    spec: localized,
    assetPrefix: '../../assets',
    rootPrefix: '../../',
    overviewHref: `../../${code}/index.html`,
    languageHref: (target) => `../${target}/index.html`,
  }));
}

console.log(`mpia docs built in ${dist}`);
