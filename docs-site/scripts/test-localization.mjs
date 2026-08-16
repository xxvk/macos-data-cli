import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { openApiPath } from './build-context.mjs';
import { inferSchemaRoles, localizeOpenApiSpec } from './localize.mjs';
import { referencePage } from './scalar-page.mjs';

const source = JSON.parse(readFileSync(openApiPath, 'utf8'));
const zh = localizeOpenApiSpec(source, 'zh-CN');
const en = localizeOpenApiSpec(source, 'en-US');
const ja = localizeOpenApiSpec(source, 'ja-JP');

const versionedPage = referencePage({
  language: 'zh-CN',
  spec: zh,
  languageHref: (language) => `../${language}/index.html`,
});
assert.match(versionedPage, /data-mpia-version="0\.9\.3"/u);

assert.equal(zh.components.schemas.CalendarEventInput.title, '日历 新建事件请求');
assert.equal(zh.components.schemas.CalendarEventPayload.title, '日历 事件详情响应');
assert.equal(zh.components.schemas.ContactPayload.title, '联系人 详情（请求/响应）');
assert.equal(zh.components.schemas.PostalAddress.title, '联系人 邮政地址结构');
assert.equal(en.components.schemas.ContactPayload.title, 'Contacts Details (request/response)');
assert.equal(ja.components.schemas.PostalAddress.title, '連絡先 郵送先住所構造');

for (const localized of [en, zh, ja]) {
  for (const schema of Object.values(localized.components.schemas)) {
    for (const property of Object.values(schema.properties ?? {})) {
      assert.ok(property.title, 'Every schema property must have a localized display title');
    }
  }
}

function compareDescriptions(sourceSchema, localizedSchema, path, language) {
  if (sourceSchema.description) {
    assert.notEqual(
      localizedSchema.description,
      sourceSchema.description,
      `Missing ${language} description for ${path}`,
    );
  }
  for (const [propertyName, sourceProperty] of Object.entries(sourceSchema.properties ?? {})) {
    compareDescriptions(sourceProperty, localizedSchema.properties[propertyName], `${path}.${propertyName}`, language);
  }
  if (sourceSchema.items) compareDescriptions(sourceSchema.items, localizedSchema.items, `${path}[]`, language);
}

for (const [name, sourceSchema] of Object.entries(source.components.schemas)) {
  compareDescriptions(sourceSchema, zh.components.schemas[name], name, 'Chinese');
  compareDescriptions(sourceSchema, ja.components.schemas[name], name, 'Japanese');
}

function withoutCliExample(description) {
  return description?.split(/\n\nCLI (?:example|示例|例):/u)[0];
}

for (const [language, localized] of [['Chinese', zh], ['Japanese', ja]]) {
  for (let index = 0; index < source.tags.length; index += 1) {
    if (source.tags[index].description) {
      assert.notEqual(localized.tags[index].description, source.tags[index].description,
        `Missing ${language} tag description for ${source.tags[index].name}`);
    }
  }
  for (const [path, sourcePath] of Object.entries(source.paths)) {
    for (const [method, sourceOperation] of Object.entries(sourcePath)) {
      const localizedOperation = localized.paths[path][method];
      if (sourceOperation.description) {
        assert.notEqual(withoutCliExample(localizedOperation.description), sourceOperation.description,
          `Missing ${language} operation description for ${method.toUpperCase()} ${path}`);
      }
      for (let index = 0; index < (sourceOperation.parameters ?? []).length; index += 1) {
        const sourceParameter = sourceOperation.parameters[index];
        if (sourceParameter.description) {
          assert.notEqual(localizedOperation.parameters[index].description, sourceParameter.description,
            `Missing ${language} parameter description for ${method.toUpperCase()} ${path} --${sourceParameter.name}`);
        }
      }
      for (const [status, sourceResponse] of Object.entries(sourceOperation.responses ?? {})) {
        if (sourceResponse.description) {
          assert.notEqual(localizedOperation.responses[status].description, sourceResponse.description,
            `Missing ${language} response description for ${method.toUpperCase()} ${path} ${status}`);
        }
      }
    }
  }
}

function compareEveryDescription(sourceValue, localizedValue, path, language) {
  if (!sourceValue || typeof sourceValue !== 'object') return;
  for (const [key, value] of Object.entries(sourceValue)) {
    const childPath = path ? `${path}.${key}` : key;
    if (key === 'description' && typeof value === 'string') {
      assert.notEqual(localizedValue[key], value, `Missing ${language} description for ${childPath}`);
    } else if (value && typeof value === 'object') {
      compareEveryDescription(value, localizedValue[key], childPath, language);
    }
  }
}

compareEveryDescription(source, zh, '', 'Chinese');
compareEveryDescription(source, ja, '', 'Japanese');

assert.deepEqual(source.components.schemas.Page.required, ['items', 'limit', 'truncated', 'complete']);
assert.equal(source.components.schemas.Page.properties.limit.minimum, 1);
assert.equal(source.components.schemas.Page.properties.limit.maximum, 200);
assert.equal(source.components.schemas.Page.properties.items.maxItems, 200);
assert.equal(zh.components.schemas.Page.properties.limit.title, '每页数量');
assert.equal(ja.components.schemas.Page.properties.nextCursor.title, '次ページカーソル');

const roleCounts = Object.values(Object.fromEntries(inferSchemaRoles(source)))
  .reduce((counts, role) => ({ ...counts, [role]: (counts[role] ?? 0) + 1 }), {});
assert.deepEqual(roleCounts, { response: 21, nested: 16, request: 16, both: 1 });

assert.equal(zh.paths['/contacts/delete'].delete.requestBody, undefined);
assert.equal(zh.paths['/contacts/avatar/replace'].put.requestBody, undefined);

console.log('localization contract tests passed');
