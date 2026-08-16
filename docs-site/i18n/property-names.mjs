// Localized, human-facing schema property names. JSON keys remain unchanged so
// examples and machine contracts stay byte-for-byte faithful to the CLI.
const zh = {
  acceptsInput: '接受输入', accountID: '账户 ID', actionCount: '操作数量', addresses: '地址',
  alarms: '提醒', allDay: '是否全天', allowsContentModifications: '是否允许修改', answered: '是否接听',
  at: '发生时间', attendees: '参与者', backend: '后端', body: '正文', bodyFormat: '正文格式',
  burstIdentifier: '连拍 ID', bytes: '字节数', cacheState: '缓存状态', calendarID: '日历 ID',
  calendarTitle: '日历名称', canContainAssets: '是否可包含资源', canContainCollections: '是否可包含集合',
  capabilities: '能力', childCount: '子项数量', city: '城市', code: '错误代码', color: '颜色', complete: '是否完整',
  completed: '是否完成', completionDate: '完成时间', contact: '联系人', contentAvailability: '内容可用状态',
  contentType: '内容类型', contractVersion: '契约版本', conversationId: '会话 ID', country: '国家',
  creationDate: '创建时间', data: '数据', dateAdded: '添加时间', department: '部门', depth: '层级深度',
  destinationFolderID: '目标文件夹 ID', destinationParentFolderID: '目标父文件夹 ID', direction: '方向', displayName: '显示名称', due: '截止时间',
  duration: '时长', durationSeconds: '时长（秒）', emails: '电子邮箱', endDate: '结束时间', error: '错误',
  estimatedAssetCount: '预计资源数量', expectedBodySHA256: '预期正文 SHA-256',
  expectedModificationDate: '预期修改时间', expectedNameSHA256: '预期名称 SHA-256',
  expectedParentFolderID: '预期父文件夹 ID', expectedSourceSHA256: '预期源文件 SHA-256',
  externalID: '外部 ID', familyName: '姓', favorite: '是否收藏', flagged: '是否标记',
  folderCount: '文件夹数量', folderID: '文件夹 ID', fullDiskAccess: '完全磁盘访问权限', givenName: '名',
  hasAlarms: '是否有提醒', hasAttachment: '是否有附件', hasRecurrenceRules: '是否重复', hidden: '是否隐藏',
  iconAvailable: '图标是否可用', id: 'ID', identifier: '标识符', imageAvailable: '头像是否可用',
  incomplete: '是否不完整', index: '索引', isDefault: '是否默认', isFromMe: '是否由本人发送',
  isICloud: '是否为 iCloud', isRead: '是否已读', items: '项目', jobTitle: '职位', kind: '类型',
  label: '标签', lastViewedDate: '最后查看时间', limit: '每页数量', limitations: '限制说明',
  listID: '列表 ID', listTitle: '列表名称', livePhoto: '是否为实况照片', location: '位置',
  mailboxCount: '邮箱数量', mailboxID: '邮箱 ID', mediaSubtypes: '媒体子类型', mediaType: '媒体类型',
  message: '错误消息', metadata: '元数据', missed: '是否未接', modificationDate: '修改时间', name: '名称',
  networkAllowed: '是否允许联网', nextAction: '后续操作', nextCursor: '下一页游标', notes: '备注',
  ok: '是否成功', operation: '操作', organizationName: '组织名称', parentFolderID: '父文件夹 ID',
  parentID: '父级 ID', passwordProtected: '是否受密码保护', permission: '授权状态', phones: '电话号码',
  phoneticFamilyName: '姓氏注音', phoneticGivenName: '名字注音', pixelHeight: '像素高度',
  pixelWidth: '像素宽度', postalCode: '邮政编码', previewText: '预览文本', priority: '优先级',
  provider: '提供者', readBackBytes: '回读字节数', readable: '是否可读', receivedAt: '接收时间',
  recurrenceRules: '重复规则', requestedBytes: '请求字节数', resourceKind: '资源类型', resources: '资源',
  saveAccepted: '是否接受保存', schemaFingerprint: '数据库结构指纹', selected: '是否已选中',
  sender: '发件人', sentAt: '发送时间', service: '服务', shared: '是否共享', sizeBytes: '大小（字节）',
  sourceIdentifier: '数据源标识符', start: '开始时间', startDate: '开始时间', state: '州或地区',
  status: '状态', street: '街道地址', subject: '主题', subtitle: '副标题', text: '文本',
  timeZone: '时区', title: '标题', totalCount: '总数', truncated: '是否截断', type: '类型',
  unread: '是否未读', unreadCount: '未读数量', url: '网址', urls: '网址', value: '值',
  variant: '变体', writable: '是否可写',
};

const ja = {
  acceptsInput: '入力受付', accountID: 'アカウント ID', actionCount: 'アクション数', addresses: '住所',
  alarms: '通知', allDay: '終日か', allowsContentModifications: '変更可能か', answered: '応答済みか',
  at: '発生日時', attendees: '参加者', backend: 'バックエンド', body: '本文', bodyFormat: '本文形式',
  burstIdentifier: 'バースト ID', bytes: 'バイト数', cacheState: 'キャッシュ状態', calendarID: 'カレンダー ID',
  calendarTitle: 'カレンダー名', canContainAssets: 'アセット格納可否', canContainCollections: 'コレクション格納可否',
  capabilities: '機能', childCount: '子項目数', city: '市区町村', code: 'エラーコード', color: '色', complete: '完全か',
  completed: '完了済みか', completionDate: '完了日時', contact: '連絡先', contentAvailability: 'コンテンツ可用性',
  contentType: 'コンテンツタイプ', contractVersion: '契約バージョン', conversationId: '会話 ID', country: '国',
  creationDate: '作成日時', data: 'データ', dateAdded: '追加日時', department: '部署', depth: '階層の深さ',
  destinationFolderID: '移動先フォルダ ID', destinationParentFolderID: '移動先親フォルダ ID', direction: '方向', displayName: '表示名', due: '期限',
  duration: '長さ', durationSeconds: '通話時間（秒）', emails: 'メールアドレス', endDate: '終了日時', error: 'エラー',
  estimatedAssetCount: '推定アセット数', expectedBodySHA256: '期待する本文 SHA-256',
  expectedModificationDate: '期待する更新日時', expectedNameSHA256: '期待する名前 SHA-256',
  expectedParentFolderID: '期待する親フォルダ ID', expectedSourceSHA256: '期待するソース SHA-256',
  externalID: '外部 ID', familyName: '姓', favorite: 'お気に入りか', flagged: 'フラグ付きか',
  folderCount: 'フォルダ数', folderID: 'フォルダ ID', fullDiskAccess: 'フルディスクアクセス', givenName: '名',
  hasAlarms: '通知ありか', hasAttachment: '添付ありか', hasRecurrenceRules: '繰り返しか', hidden: '非表示か',
  iconAvailable: 'アイコン利用可否', id: 'ID', identifier: '識別子', imageAvailable: '画像利用可否',
  incomplete: '不完全か', index: 'インデックス', isDefault: 'デフォルトか', isFromMe: '自分からの送信か',
  isICloud: 'iCloud か', isRead: '既読か', items: '項目', jobTitle: '役職', kind: '種類',
  label: 'ラベル', lastViewedDate: '最終閲覧日時', limit: 'ページ件数', limitations: '制限事項',
  listID: 'リスト ID', listTitle: 'リスト名', livePhoto: 'Live Photo か', location: '場所',
  mailboxCount: 'メールボックス数', mailboxID: 'メールボックス ID', mediaSubtypes: 'メディアサブタイプ',
  mediaType: 'メディアタイプ', message: 'エラーメッセージ', metadata: 'メタデータ', missed: '不在着信か', modificationDate: '更新日時',
  name: '名前', networkAllowed: 'ネットワーク許可', nextAction: '次の操作', nextCursor: '次ページカーソル',
  notes: 'メモ', ok: '成功か', operation: '操作', organizationName: '組織名', parentFolderID: '親フォルダ ID',
  parentID: '親 ID', passwordProtected: 'パスワード保護か', permission: '認可状態', phones: '電話番号',
  phoneticFamilyName: '姓のふりがな', phoneticGivenName: '名のふりがな', pixelHeight: 'ピクセル高',
  pixelWidth: 'ピクセル幅', postalCode: '郵便番号', previewText: 'プレビューテキスト', priority: '優先度',
  provider: 'プロバイダー', readBackBytes: '読み戻しバイト数', readable: '読み取り可能か', receivedAt: '受信日時',
  recurrenceRules: '繰り返し規則', requestedBytes: '要求バイト数', resourceKind: 'リソース種類', resources: 'リソース',
  saveAccepted: '保存受付済みか', schemaFingerprint: 'スキーマ指紋', selected: '選択中か', sender: '送信者',
  sentAt: '送信日時', service: 'サービス', shared: '共有か', sizeBytes: 'サイズ（バイト）',
  sourceIdentifier: 'ソース識別子', start: '開始日時', startDate: '開始日時', state: '都道府県・地域',
  status: '状態', street: '住所', subject: '件名', subtitle: 'サブタイトル', text: 'テキスト',
  timeZone: 'タイムゾーン', title: 'タイトル', totalCount: '総数', truncated: '切り詰めありか', type: '種類',
  unread: '未読か', unreadCount: '未読数', url: 'URL', urls: 'URL', value: '値', variant: 'バリアント',
  writable: '書き込み可能か',
};

function englishName(name) {
  return name
    .replace(/ID/g, ' ID')
    .replace(/SHA256/g, ' SHA-256')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/^./, (letter) => letter.toUpperCase())
    .replace(/\s+/g, ' ')
    .trim();
}

export function propertyDisplayName(name, language) {
  if (language === 'zh-CN') return zh[name];
  if (language === 'ja-JP') return ja[name];
  return englishName(name);
}

export const localizedPropertyKeys = new Set([...Object.keys(zh), ...Object.keys(ja)]);
