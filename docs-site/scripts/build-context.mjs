import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const docsSiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const repoRoot = resolve(docsSiteRoot, '..');
// Vercel builds into the repository docs-site/dist by default; tests override it.
export const dist = process.env.MPIA_DOCS_DIST
  ? resolve(process.env.MPIA_DOCS_DIST)
  : resolve(docsSiteRoot, 'dist');

export const languages = [
  { code: 'en-US', label: 'English', scalarLocale: 'en' },
  { code: 'zh-CN', label: '简中', scalarLocale: 'zh-CN' },
  { code: 'ja-JP', label: '日本語', scalarLocale: 'ja-JP' },
];

export const defaultLanguage = 'en-US';

// The committed OpenAPI view of the CLI (regenerated locally, never on Vercel).
export const openApiPath = resolve(repoRoot, 'docs', 'openapi.json');
