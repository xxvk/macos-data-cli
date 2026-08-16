import { translations } from '../i18n/translations.mjs';
import { resourceNames, leafNames } from '../i18n/display-names.mjs';

function translate(value, table) {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(table, value)
    ? table[value]
    : value;
}

function localizeSchema(schema, table) {
  if (!schema || typeof schema !== 'object') return;
  if (schema.description) schema.description = translate(schema.description, table);
  for (const prop of Object.values(schema.properties ?? {})) localizeSchema(prop, table);
  if (schema.items) localizeSchema(schema.items, table);
}

function displayName(group, leaf, language) {
  const resource = resourceNames[group]?.[language] ?? group;
  const action = leafNames[leaf]?.[language] ?? leaf;
  // CJK concatenates without a space; English keeps a space.
  return language === 'en-US' ? `${resource} ${action}` : `${resource}${action}`;
}

const cliExampleLabels = {
  'en-US': 'CLI example',
  'zh-CN': 'CLI 示例',
  'ja-JP': 'CLI 例',
};

// Token colors (A-E) live in site/scalar-shell.css as .mpia-cli-* classes.
function colorizeCli(command) {
  // Tokenize, keeping quoted strings ("..."/'...') as single tokens so values
  // with spaces (e.g. --confirm "DELETE CONTACT") color as one value token.
  const tokens = command.match(/"([^"]*)"|'([^']*)'|\S+/g) ?? [];
  return tokens.map((token, index) => {
    let cls;
    if (index === 0) cls = 'mpia-cli-name';
    else if (index === 1) cls = 'mpia-cli-module';
    else if (token.startsWith('-')) cls = 'mpia-cli-flag';
    else if (/^["']/.test(token)) cls = 'mpia-cli-value';
    else cls = 'mpia-cli-action';
    return `<span class="${cls}">${token}</span>`;
  }).join(' ');
}

export function localizeOpenApiSpec(spec, language) {
  const table = translations[language] ?? {};
  const clone = structuredClone(spec);
  const tagNameMap = {};

  // 1. Localize tags first, recording old->new name mapping so operations stay in sync.
  for (const tag of clone.tags ?? []) {
    if (tag.description) tag.description = translate(tag.description, table);
    if (language !== 'en-US') {
      const base = (tag.name || '').replace(/^\d+\.\s*/, '');
      const resource = resourceNames[base]?.[language];
      if (resource) {
        tagNameMap[tag.name] = `${tag.name} ${resource}`;
        tag.name = tagNameMap[tag.name];
      }
    }
  }

  // 2. Localize operations (summary, description, params, and their tags).
  for (const pathItem of Object.values(clone.paths ?? {})) {
    for (const operation of Object.values(pathItem ?? {})) {
      if (!operation || typeof operation !== 'object') continue;

      const number = (operation.summary || '').split(' ')[0];
      const group = operation['x-group'];
      const leaf = operation['x-leaf'];
      if (number && group && leaf) {
        if (group === leaf) {
          const name = language === 'en-US' ? group : (resourceNames[group]?.[language] ?? group);
          operation.summary = `${number} ${name}`;
        } else {
          operation.summary = `${number} ${displayName(group, leaf, language)}`;
        }
      }

      if (operation.description) operation.description = translate(operation.description, table);
      if (operation['x-cli-command']) {
        const cliLabel = cliExampleLabels[language] ?? 'CLI example';
        operation.description = `${operation.description || ''}\n\n${cliLabel}: <code>${colorizeCli(operation['x-cli-command'])}</code>`.trim();
      }

      if (Array.isArray(operation.tags)) {
        operation.tags = operation.tags.map((t) => tagNameMap[t] ?? t);
      }

      for (const param of operation.parameters ?? []) {
        if (param.description) param.description = translate(param.description, table);
      }
    }
  }

  // 3. Localize schemas.
  for (const schema of Object.values(clone.components?.schemas ?? {})) {
    localizeSchema(schema, table);
  }

  if (clone.info?.description) {
    clone.info.description = translate(clone.info.description, table);
  }
  return clone;
}
