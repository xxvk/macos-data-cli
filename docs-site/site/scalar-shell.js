(function () {
  var labels = {
    'en-US': { overview: 'Overview', version: 'Version' },
    'zh-CN': { overview: '概览', version: '版本' },
    'ja-JP': { overview: '概要', version: 'バージョン' },
  };

  function lang() {
    return document.documentElement.lang || 'en-US';
  }

  function text(key) {
    return (labels[lang()] || labels['en-US'])[key];
  }

  function install() {
    var aside = document.querySelector('aside');
    var nav = aside ? aside.querySelector('ul') : null;
    if (!aside || !nav) return false;

    if (!aside.querySelector('.mpia-sidebar-links')) {
      var overviewHref = document.body.dataset.mpiaOverviewHref;
      if (overviewHref) {
        var overviewLi = document.createElement('li');
        overviewLi.className = 'mpia-sidebar-links';
        var overview = document.createElement('a');
        overview.className = 'mpia-overview-link';
        overview.href = overviewHref;
        overview.textContent = text('overview');
        overviewLi.append(overview);
        nav.prepend(overviewLi);
      }

      var template = document.getElementById('mpia-language-switcher-template');
      if (template && template.content.firstElementChild) {
        var switcherLi = document.createElement('li');
        switcherLi.className = 'mpia-language-switcher-item';
        switcherLi.append(template.content.firstElementChild.cloneNode(true));
        nav.prepend(switcherLi);
      }
    }

    var footer = aside.querySelector('.darklight-reference');
    if (footer && !footer.querySelector('.mpia-version-label')) {
      var label = document.createElement('span');
      label.className = 'mpia-version-label';
      label.textContent = text('version') + ' 0.9.0';
      footer.insertAdjacentElement('beforebegin', label);
    }

    return true;
  }

  var tries = 0;
  var timer = setInterval(function () {
    if (install() || ++tries > 150) clearInterval(timer);
  }, 100);
})();
