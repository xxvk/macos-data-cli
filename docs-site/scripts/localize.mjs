import { translations } from '../i18n/translations.mjs';
import { commandTranslations } from '../i18n/command-translations.mjs';
import { descriptionTranslationsZh } from '../i18n/description-translations-zh.mjs';
import { descriptionTranslationsJa } from '../i18n/description-translations-ja.mjs';
import { resourceNames, leafNames } from '../i18n/display-names.mjs';
import { propertyDisplayName } from '../i18n/property-names.mjs';
import {
  schemaDomainNames,
  schemaDomainOrder,
  schemaNames,
  schemaRoleSuffixes,
} from '../i18n/schema-names.mjs';

function translate(value, table) {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(table, value)
    ? table[value]
    : value;
}

function localizeSchema(schema, table, language, fallbackTitle) {
  if (!schema || typeof schema !== 'object') return;
  if (schema.description) {
    const originalDescription = schema.description;
    schema.description = translate(schema.description, table);
    if (language !== 'en-US' && schema.description === originalDescription) {
      const title = schema.title ?? fallbackTitle ?? (language === 'ja-JP' ? '項目' : '项目');
      schema.description = `${title}。`;
    }
  }
  for (const [name, prop] of Object.entries(schema.properties ?? {})) {
    const propertyTitle = propertyDisplayName(name, language);
    if (!propertyTitle) throw new Error(`Missing ${language} property title for ${name}`);
    prop.title = propertyTitle;
    localizeSchema(prop, table, language, propertyTitle);
  }
  if (schema.items) {
    const itemTitle = language === 'ja-JP' ? '配列項目' : language === 'zh-CN' ? '数组项目' : 'Array item';
    localizeSchema(schema.items, table, language, itemTitle);
  }
}

function referencedSchemaNames(schema, names = new Set()) {
  if (!schema || typeof schema !== 'object') return names;
  const ref = schema.$ref;
  if (typeof ref === 'string' && ref.startsWith('#/components/schemas/')) {
    names.add(ref.slice('#/components/schemas/'.length));
  }
  for (const value of Object.values(schema)) referencedSchemaNames(value, names);
  return names;
}

export function inferSchemaRoles(spec) {
  const roles = new Map(Object.keys(spec.components?.schemas ?? {}).map((name) => [name, new Set()]));
  for (const pathItem of Object.values(spec.paths ?? {})) {
    for (const operation of Object.values(pathItem ?? {})) {
      if (!operation || typeof operation !== 'object') continue;
      const requestSchema = operation.requestBody?.content?.['application/json']?.schema;
      for (const requestName of referencedSchemaNames(requestSchema)) roles.get(requestName)?.add('request');
      for (const response of Object.values(operation.responses ?? {})) {
        const responseSchema = response?.content?.['application/json']?.schema;
        for (const responseName of referencedSchemaNames(responseSchema)) roles.get(responseName)?.add('response');
      }
    }
  }
  return new Map([...roles].map(([name, uses]) => {
    if (uses.size === 0) return [name, 'nested'];
    if (uses.size === 2) return [name, 'both'];
    return [name, uses.has('request') ? 'request' : 'response'];
  }));
}

function displayName(group, leaf, language) {
  const resource = resourceNames[group]?.[language] ?? group;
  const composite = leafNames[`${group} ${leaf}`]?.[language];
  if (composite) return composite;
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
  const currentDescriptions = language === 'zh-CN'
    ? descriptionTranslationsZh
    : language === 'ja-JP' ? descriptionTranslationsJa : {};
  const table = {
    ...(translations[language] ?? {}),
    ...(commandTranslations[language] ?? {}),
    ...currentDescriptions,
  };
  const clone = structuredClone(spec);
  const tagNameMap = {};

  // 1. Localize tags first, recording old->new name mapping so operations stay in sync.
  for (const tag of clone.tags ?? []) {
    if (tag.description) tag.description = translate(tag.description, table);
    const base = (tag.name || '').replace(/^(?:\d+|[Aa])\.\s*/, '');
    const resource = resourceNames[base]?.[language];
    if (resource) {
      tagNameMap[tag.name] = `${tag.name} ${resource}`;
      tag.name = tagNameMap[tag.name];
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
      for (const response of Object.values(operation.responses ?? {})) {
        if (response?.description) response.description = translate(response.description, table);
      }
      for (const exitCode of operation['x-exit-codes'] ?? []) {
        if (exitCode.description) exitCode.description = translate(exitCode.description, table);
      }
    }
  }

  // 3. Localize schemas.
  const schemas = clone.components?.schemas ?? {};
  const schemaRoles = inferSchemaRoles(clone);
  const roleSuffixes = schemaRoleSuffixes[language];
  for (const [name, schema] of Object.entries(schemas)) {
    const definition = schemaNames[name];
    const domain = schemaDomainNames[definition?.domain]?.[language];
    const title = definition?.[language];
    if (!domain || !title) throw new Error(`Missing ${language} domain/title for schema ${name}`);
    const separator = definition.separator?.[language] ?? ' ';
    const role = schemaRoles.get(name);
    const roleSuffix = roleSuffixes?.[role];
    if (!roleSuffix) throw new Error(`Missing ${language} role suffix for schema ${name}`);
    schema.title = `${domain}${separator}${title}${roleSuffix}`;
    localizeSchema(schema, table, language);
  }
  clone.components.schemas = Object.fromEntries(
    Object.entries(schemas).sort(([left], [right]) => {
      const leftDomain = schemaNames[left].domain;
      const rightDomain = schemaNames[right].domain;
      const domainDifference = schemaDomainOrder.indexOf(leftDomain) - schemaDomainOrder.indexOf(rightDomain);
      return domainDifference || left.localeCompare(right);
    }),
  );

  if (clone.info?.description) {
    clone.info.description = translate(clone.info.description, table);
  }
  return clone;
}
