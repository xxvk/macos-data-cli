(function () {
  var labels = {
    'en-US': { version: 'Version', apiTest: 'Open API test tool', apiTestUnavailable: 'API test tool unavailable' },
    'zh-CN': { version: '版本', apiTest: '打开 API 测试工具', apiTestUnavailable: 'API 测试工具不可用' },
    'ja-JP': { version: 'バージョン', apiTest: 'API テストツールを開く', apiTestUnavailable: 'API テストツールを利用できません' },
  };

  var svgNamespace = 'http://www.w3.org/2000/svg';
  var iconPaths = {
    'squares-four': 'M104,40H56A16,16,0,0,0,40,56v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,104,40Zm0,64H56V56h48ZM200,40H152a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,200,40Zm0,64H152V56h48ZM104,136H56a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V152A16,16,0,0,0,104,136Zm0,64H56V152h48Zm96-64H152a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V152A16,16,0,0,0,200,136Zm0,64H152V152h48Z',
    'user': 'M230.92,212c-15.23-26.33-38.7-45.21-66.09-54.16a72,72,0,1,0-73.66,0C63.78,166.78,40.31,185.66,25.08,212a8,8,0,1,0,13.85,8c18.84-32.56,52.14-52,89.07-52s70.23,19.44,89.07,52a8,8,0,1,0,13.85-8ZM72,96a56,56,0,1,1,56,56A56.06,56.06,0,0,1,72,96Z',
    'envelope': 'M224,48H32a8,8,0,0,0-8,8V192a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A8,8,0,0,0,224,48ZM203.43,64,128,133.15,52.57,64ZM216,192H40V74.19l82.59,75.71a8,8,0,0,0,10.82,0L216,74.19Z',
    'calendar': 'M208,32H184V24a8,8,0,0,0-16,0v8H88V24a8,8,0,0,0-16,0v8H48A16,16,0,0,0,32,48V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V48A16,16,0,0,0,208,32ZM72,48v8a8,8,0,0,0,16,0V48h80v8a8,8,0,0,0,16,0V48h24V80H48V48ZM208,208H48V96H208Z',
    'check-circle': 'M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm45.66,85.66-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z',
    'image': 'M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,160H40V56H216V200ZM216,160l-40-40-24,24-40-40L56,160v40H200ZM96,80a16,16,0,1,0,16,16A16,16,0,0,0,96,80Z',
    'note': 'M208,32H48A16,16,0,0,0,32,48V208a16,16,0,0,0,16,16H156.69a15.86,15.86,0,0,0,11.31-4.69L212.69,174.69A15.86,15.86,0,0,0,216,163.31V48A16,16,0,0,0,208,32ZM48,48H208V152H160a8,8,0,0,0-8,8v48H48ZM196.69,168,168,196.69V168Z',
    'lightning': 'M215.79,118.17a8,8,0,0,0-5-5.66L153.18,90.9l14.66-73.33a8,8,0,0,0-13.69-7L22.27,132.26a8,8,0,0,0,3,13.13l58.36,21.87-14.66,73.33a8,8,0,0,0,13.69,7l131.87-121.66A8,8,0,0,0,215.79,118.17Z',
    'compass': 'M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm57.66-105.66-32,64a8,8,0,0,1-3.62,3.62l-64,32a8,8,0,0,1-10.66-10.66l32-64a8,8,0,0,1,3.62-3.62l64-32a8,8,0,0,1,10.66,10.66Z',
  };

  var groupIcons = {
    resources: 'squares-four',
    contacts: 'user',
    mail: 'envelope',
    calendar: 'calendar',
    reminders: 'check-circle',
    photos: 'image',
    notes: 'note',
    shortcuts: 'lightning',
    safari: 'compass',
  };

  function lang() {
    return document.documentElement.lang || 'en-US';
  }

  function text(key) {
    return (labels[lang()] || labels['en-US'])[key];
  }

  function install() {
    // Remove the "Powered by Scalar" attribution (desktop + mobile).
    document.querySelectorAll('a[href^="https://www.scalar.com"]').forEach(function (a) { a.remove(); });

    var aside = document.querySelector('aside');
    var nav = aside ? aside.querySelector('ul') : null;
    if (!aside || !nav) return false;

    if (!aside.querySelector('.mpia-language-switcher-item')) {
      var template = document.getElementById('mpia-language-switcher-template');
      if (template && template.content.firstElementChild) {
        var switcherLi = document.createElement('li');
        switcherLi.className = 'mpia-language-switcher-item';
        switcherLi.append(template.content.firstElementChild.cloneNode(true));
        nav.prepend(switcherLi);
      }
    }

    document.querySelectorAll('aside').forEach(function (a) { installGroupIcons(a); });
    installApiTestTool(aside);

    // Put the version label in the same row as the dark-mode toggle,
    // left-aligned (the label grows to push the toggle to the right edge).
    var footer = aside.querySelector('.darklight-reference');
    var toggle = footer ? footer.querySelector('button[aria-pressed]') : null;
    var themeRow = toggle ? toggle.parentElement : null;
    if (themeRow && !themeRow.querySelector('.mpia-version-label')) {
      themeRow.classList.add('mpia-theme-row');
      var label = document.createElement('span');
      label.className = 'mpia-version-label';
      label.textContent = text('version') + ' 0.9.0';
      themeRow.insertAdjacentElement('afterbegin', label);
    }

    return true;
  }

  function createGroupIcon(name) {
    var svg = document.createElementNS(svgNamespace, 'svg');
    svg.classList.add('mpia-group-icon');
    svg.setAttribute('viewBox', '0 0 256 256');
    svg.setAttribute('fill', 'currentColor');
    svg.setAttribute('aria-hidden', 'true');
    var path = document.createElementNS(svgNamespace, 'path');
    path.setAttribute('d', iconPaths[name]);
    svg.append(path);
    return svg;
  }

  function installGroupIcons(aside) {
    for (const item of aside.querySelectorAll('[data-sidebar-id]')) {
      if (item.querySelector('.mpia-group-icon')) continue;
      const label = [...item.querySelectorAll('button > div')]
        .find((element) => element.classList.contains('group/button-label'));
      if (!label) continue;
      // The label is "N. <english> <localized>" (e.g. "0. resources 资源"),
      // so strip the number and keep the leading English token for the lookup.
      const base = label.textContent.trim().replace(/^\d+\.\s*/, '').split(/\s+/)[0];
      const iconName = groupIcons[base];
      if (!iconName) continue;
      label.insertAdjacentElement('beforebegin', createGroupIcon(iconName));
    }
  }

  // Open the built-in Scalar API client by clicking the operation's
  // "Test Request" button (which emits ui:open:client-modal). If none is
  // mounted yet, expand the first operation and retry.
  function openApiTestTool(attempt) {
    var testRequest = document.querySelector('.show-api-client-button');
    if (testRequest) {
      testRequest.click();
      revealClientSidebar(0, document);
      return;
    }
    if (attempt === 0) {
      var aside = document.querySelector('aside');
      var items = aside ? aside.querySelectorAll('[data-sidebar-id]') : [];
      var firstOperation = Array.prototype.slice.call(items).find(function (item) {
        return /\/(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE)\//.test(item.getAttribute('data-sidebar-id') || '');
      });
      var opButton = firstOperation ? firstOperation.querySelector('button') : null;
      if (opButton) opButton.click();
    }
    if (attempt < 60) {
      window.setTimeout(function () { openApiTestTool(attempt + 1); }, 50);
      return;
    }
    window.alert(text('apiTestUnavailable'));
  }

  function revealClientSidebar(attempt, root) {
    var client = (root || document).querySelector('[role="dialog"].scalar-client');
    var sidebarToggle = client ? client.querySelector('.scalar-sidebar-toggle') : null;
    if (sidebarToggle) {
      if (sidebarToggle.getAttribute('aria-pressed') !== 'true') sidebarToggle.click();
      return;
    }
    if (attempt < 60) {
      window.setTimeout(function () { revealClientSidebar(attempt + 1, root); }, 50);
    }
  }

  // Replace Scalar's "VS Code / Cursor / Generate MCP" footer row with a single
  // "Open API test tool" button (matching aim-robot-platform).
  function installApiTestTool(aside) {
    var footer = aside.querySelector('.darklight-reference');
    if (!footer) return false;

    var mcpLayer = footer.querySelector('.scalar-mcp-layer');
    if (mcpLayer) mcpLayer.remove();

    var trigger = footer.querySelector('.mpia-api-test-button');
    if (!trigger) {
      trigger = document.createElement('button');
      trigger.className = 'mpia-api-test-button';
      trigger.type = 'button';
      trigger.textContent = text('apiTest');
      footer.prepend(trigger);
    }
    if (trigger.dataset.mpiaApiTestInstalled === 'true') return true;
    trigger.dataset.mpiaApiTestInstalled = 'true';
    trigger.addEventListener('click', function () { openApiTestTool(0); });
    return true;
  }

  var tries = 0;
  var timer = setInterval(function () {
    if (install() || ++tries > 150) clearInterval(timer);
  }, 100);
})();
