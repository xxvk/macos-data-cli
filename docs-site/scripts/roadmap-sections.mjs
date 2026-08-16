const copy = {
  'en-US': {
    group: '10. phone-calls (planned)',
    tag: 'Planned read-only recent call-history adapter for 0.9.2.',
    permission: '10.1 phone-calls permission (planned)',
    permissionDescription: 'Planned status-only permission probe. No phone-calls CLI command is available yet.',
    recent: '10.2 phone-calls recent (planned)',
    recentDescription: 'Planned bounded recent-call query. No phone-calls CLI command is available yet.',
    unavailable: 'Planned for mpia 0.9.2; unavailable in the current CLI.',
  },
  'zh-CN': {
    group: '10. phone-calls 通话记录（规划中）',
    tag: '计划在 0.9.2 提供只读的最近通话记录 adapter。',
    permission: '10.1 通话记录权限（规划中）',
    permissionDescription: '计划中的仅状态权限检查。当前 CLI 尚无 phone-calls 命令。',
    recent: '10.2 最近通话（规划中）',
    recentDescription: '计划中的有界最近通话查询。当前 CLI 尚无 phone-calls 命令。',
    unavailable: '计划在 mpia 0.9.2 提供；当前 CLI 尚不可用。',
  },
  'ja-JP': {
    group: '10. phone-calls 通話履歴（計画中）',
    tag: '0.9.2 で読み取り専用の最近の通話履歴アダプターを提供する予定です。',
    permission: '10.1 通話履歴の権限（計画中）',
    permissionDescription: '状態確認のみの権限プローブを予定しています。現在の CLI には phone-calls コマンドがありません。',
    recent: '10.2 最近の通話（計画中）',
    recentDescription: '境界付きの最近の通話クエリを予定しています。現在の CLI には phone-calls コマンドがありません。',
    unavailable: 'mpia 0.9.2 で提供予定です。現在の CLI では利用できません。',
  },
};

function operation(summary, description, method, tag) {
  return {
    [method]: {
      summary,
      description,
      responses: { 501: { description: copyDescription(tag) } },
      tags: [tag],
      'x-status': 'planned',
      'x-cli-available': false,
      'x-safety': { apply: false, dryRun: false },
    },
  };
}

function copyDescription(tag) {
  return Object.values(copy).find((item) => item.group === tag)?.unavailable
    ?? copy['en-US'].unavailable;
}

export function addRoadmapSections(spec, language) {
  if (spec.paths?.['/phone-calls/permission']) return spec;
  const text = copy[language] ?? copy['en-US'];
  spec.tags ??= [];
  spec.paths ??= {};
  spec.tags.push({ name: text.group, description: text.tag, 'x-status': 'planned' });
  spec.paths['/phone-calls/permission'] = operation(
    text.permission, text.permissionDescription, 'options', text.group,
  );
  spec.paths['/phone-calls/recent'] = operation(
    text.recent, text.recentDescription, 'get', text.group,
  );
  return spec;
}
