import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { dist, docsSiteRoot, languages, openApiPath } from './build-context.mjs';
import { localizeOpenApiSpec } from './localize.mjs';
import { addRoadmapSections } from './roadmap-sections.mjs';
import { referencePage } from './scalar-page.mjs';

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

const semanticsHeadings = {
  'en-US': 'OpenAPI semantic mapping',
  'zh-CN': 'OpenAPI 语义映射',
  'ja-JP': 'OpenAPI の意味マッピング',
};

// The overview is rendered by Scalar as the spec's `info.description`, exactly
// like aim-robot-platform: no separate landing page.
for (const { code } of languages) {
  const localized = localizeOpenApiSpec(sourceSpec, code);
  addRoadmapSections(localized, code);
  const overviewMarkdown = readFileSync(resolve(docsSiteRoot, 'guides', code, 'overview.md'), 'utf8');
  const cliVsMcpMarkdown = readFileSync(resolve(docsSiteRoot, 'guides', code, 'cli-vs-mcp.md'), 'utf8');
  localized.info.description = [
    overviewMarkdown.trim(),
    `### ${semanticsHeadings[code]}\n\n${localized.info.description.trim()}`,
    cliVsMcpMarkdown.trim(),
  ].join('\n\n');

  mkdirSync(resolve(dist, code), { recursive: true });
  writeFileSync(resolve(dist, code, 'index.html'), referencePage({
    language: code,
    spec: localized,
    assetPrefix: '../assets',
    rootPrefix: '../',
    languageHref: (target) => `../${target}/index.html`,
  }));
}

console.log(`mpia docs built in ${dist}`);
