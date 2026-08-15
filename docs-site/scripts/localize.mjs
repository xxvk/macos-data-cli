import { translations } from '../i18n/translations.mjs';

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

export function localizeOpenApiSpec(spec, language) {
  if (language === 'en-US') return spec;
  const table = translations[language] ?? {};
  const clone = structuredClone(spec);
  for (const pathItem of Object.values(clone.paths ?? {})) {
    for (const operation of Object.values(pathItem ?? {})) {
      if (!operation || typeof operation !== 'object') continue;
      if (operation.summary) operation.summary = translate(operation.summary, table);
      if (operation.description) operation.description = translate(operation.description, table);
      for (const param of operation.parameters ?? []) {
        if (param.description) param.description = translate(param.description, table);
      }
    }
  }
  for (const schema of Object.values(clone.components?.schemas ?? {})) {
    localizeSchema(schema, table);
  }
  return clone;
}
