// 원 홈페이지 템플릿(index/forest/carnival/gallery) 공통 topbar 렌더러.
// 햄버거 메뉴(menu-btn/menu-panel)는 각 템플릿 HTML에 그대로 남아있고, 이 모듈이 actions 영역으로 옮겨 담는다.
window.WoniyaTopbar = (function(){
  var STYLE_ID = 'woniya-topbar-style';

  function ensureStyle(){
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent =
      '.topbar .wrap{max-width:560px;margin:0 auto;padding:0 22px;display:flex;align-items:center;justify-content:space-between}' +
      '.topbar-actions{display:flex;align-items:center;gap:16px}' +
      '.topbar-home{display:flex;color:var(--ink-soft);transition:color .2s ease}' +
      '.topbar-home:hover{color:var(--coral)}' +
      '.topbar-home svg{width:22px;height:22px;display:block}' +
      '.topbar-actions .menu-btn{visibility:visible}' +
      '.topbar-preview-badge{display:inline-flex;align-items:center;min-height:26px;padding:4px 9px;border-radius:5px 13px 5px 13px;background:rgba(86,115,74,.12);color:#425c3d;font-size:.72rem;font-weight:800;white-space:nowrap}' +
      '.topbar.topbar-forest{padding:14px 0;background:rgba(251,251,244,.9);box-shadow:0 1px 0 rgba(74,107,58,.14);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);filter:none;-webkit-mask:none;mask:none}' +
      '.topbar.topbar-forest .wrap{width:100%;max-width:1320px;padding:0 clamp(24px,4vw,72px)}' +
      '.topbar.topbar-forest .brand{display:flex;align-items:center;gap:8px;color:#314f3c;font-family:var(--display,serif);font-size:1.3rem;font-weight:700;text-decoration:none;letter-spacing:-.5px}' +
      '.topbar.topbar-forest .brand::before{content:"";width:18px;height:18px;flex:none;background:#769365;border-radius:0 50% 50% 50%;transform:rotate(45deg)}' +
      '.topbar.topbar-forest .topbar-home{color:#425c3d}' +
      '.topbar.topbar-forest .topbar-home:hover{color:#314f3c}' +
      '.topbar.topbar-compact{padding:8px 0;filter:none;-webkit-mask:none;mask:none;box-shadow:0 1px 0 rgba(120,80,60,.12)}' +
      '.topbar.topbar-compact .wrap{width:100%;max-width:560px;min-width:0;padding:0 14px;gap:9px}' +
      '.topbar.topbar-compact .brand{display:block;flex:1 1 auto;min-width:0;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:clamp(.98rem,4.8vw,1.14rem);line-height:1.3}' +
      '.topbar.topbar-compact .topbar-actions{flex:0 0 auto;min-width:0;max-width:48%;gap:8px}' +
      '.topbar.topbar-compact .topbar-actions>*{flex:0 1 auto;min-width:0;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.topbar.topbar-compact .topbar-actions>.topbar-home,.topbar.topbar-compact .topbar-actions>.menu-btn{flex:0 0 auto}' +
      '.topbar.topbar-compact .topbar-actions>:focus-visible{outline:2px solid currentColor;outline-offset:-2px}' +
      '.topbar.topbar-compact .brand[aria-disabled="true"]{pointer-events:none;cursor:default}' +
      '.topbar.topbar-compact.topbar-forest .brand::before{display:inline-block;vertical-align:-2px;margin-right:8px}' +
      'body.theme-forest .menu-panel{top:78px;right:max(clamp(24px,4vw,72px),calc((100vw - 1320px)/2 + clamp(24px,4vw,72px)));left:auto;width:clamp(240px,25vw,340px);max-width:calc(100vw - 40px);max-height:calc(100vh - 98px);overflow-y:auto;padding:12px;background:linear-gradient(145deg,rgba(251,249,239,.98),rgba(232,234,215,.98));border:1px solid rgba(86,115,74,.16);border-radius:28px 16px 30px 18px / 20px 30px 18px 28px;box-shadow:0 24px 54px -28px rgba(32,56,44,.58)}' +
      'body.theme-forest .menu-panel a{padding:13px 16px;border-radius:6px 17px 6px 17px;color:#314f3c}' +
      'body.theme-forest .menu-panel a:hover,body.theme-forest .menu-panel a:focus-visible{background:rgba(118,147,101,.14)}' +
      '@media(max-width:600px){.topbar.topbar-forest .wrap{padding:0 20px}.topbar.topbar-forest .brand{max-width:min(48vw,210px);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:1.05rem}.topbar.topbar-forest .topbar-actions{gap:9px}.topbar-preview-badge{max-width:86px;overflow:hidden;text-overflow:ellipsis;padding-inline:7px;font-size:.66rem}body.theme-forest .menu-panel{top:74px;right:20px;left:auto;width:min(86vw,320px);max-width:calc(100vw - 40px)}.topbar.topbar-compact .wrap{padding:0 12px;gap:7px}.topbar.topbar-compact .brand{max-width:100%;font-size:clamp(.94rem,4.8vw,1.05rem)}.topbar.topbar-compact .topbar-actions{gap:6px}}';
    document.head.appendChild(style);
  }

  var HOME_ICON_SVG =
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M3 9.5L12 3l9 6.5V20a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V9.5z"/>' +
      '<polyline points="9 21 9 12 15 12 15 21"/>' +
    '</svg>';

  function hasOwn(object, key){
    return Object.prototype.hasOwnProperty.call(object, key);
  }

  function cleanText(value, fallback){
    var text = String(value == null ? '' : value).trim();
    return text || fallback;
  }

  function isManagedTopbar(nav){
    return !!nav && nav.getAttribute('data-woniya-topbar') === 'true';
  }

  function setBrandState(brand, options, allowLegacyFallback, normalizeName){
    brand.textContent = normalizeName
      ? cleanText(options.centerName, '우리 원')
      : (options.centerName || '원이야');

    var brandHref = cleanText(options.brandHref, '');
    if (!brandHref && allowLegacyFallback) {
      brandHref = cleanText(options.homeHref, '') || '#top';
    }
    if (options.brandDisabled === true || !brandHref) {
      brand.removeAttribute('href');
      brand.setAttribute('aria-disabled', 'true');
      brand.setAttribute('tabindex', '-1');
      return;
    }
    brand.href = brandHref;
    brand.removeAttribute('aria-disabled');
    brand.removeAttribute('tabindex');
  }

  function syncActions(actions, options){
    var previewBadge = actions.querySelector('.topbar-preview-badge');
    if (options.previewLabel) {
      if (!previewBadge) {
        previewBadge = document.createElement('span');
        previewBadge.className = 'topbar-preview-badge';
      }
      previewBadge.textContent = options.previewLabel;
      actions.appendChild(previewBadge);
    } else if (previewBadge) {
      previewBadge.remove();
    }

    var home = actions.querySelector('.topbar-home');
    if (options.showHome === false) {
      if (home) home.remove();
    } else {
      if (!home) {
        home = document.createElement('a');
        home.className = 'topbar-home';
        home.setAttribute('aria-label', '홈으로');
        home.innerHTML = HOME_ICON_SVG;
      }
      home.href = options.homeHref || 'index.html';
      actions.appendChild(home);
    }

    var menuBtn = document.getElementById('menuBtn');
    var actionElement = options.actionElement && options.actionElement.nodeType === 1
      ? options.actionElement
      : null;
    if (actionElement) actionElement.setAttribute('data-woniya-topbar-action', 'true');
    var managedActions = Array.prototype.filter.call(actions.children, function(child){
      return child.getAttribute('data-woniya-topbar-action') === 'true';
    });
    if (menuBtn) actions.appendChild(menuBtn);
    managedActions.forEach(function(action){ actions.appendChild(action); });
    if (actionElement && managedActions.indexOf(actionElement) < 0) actions.appendChild(actionElement);
  }

  function init(options){
    options = options || {};

    var existingNav = document.getElementById('topbar');
    if (existingNav && !isManagedTopbar(existingNav)) return existingNav;

    ensureStyle();

    if (existingNav) {
      var existingBrand = existingNav.querySelector('#brandLink');
      var existingActions = existingNav.querySelector('.topbar-actions');
      if (!existingBrand || !existingActions) return existingNav;
      existingNav.classList.toggle('topbar-forest', options.theme === 'forest');
      existingNav.classList.toggle('topbar-compact', options.compact === true);
      setBrandState(existingBrand, options, options.compact !== true && !hasOwn(options, 'brandDisabled') && !hasOwn(options, 'brandHref'), options.compact === true);
      syncActions(existingActions, options);
      return existingNav;
    }

    var nav = document.createElement('nav');
    nav.className = 'topbar' +
      (options.theme === 'forest' ? ' topbar-forest' : '') +
      (options.compact === true ? ' topbar-compact' : '');
    nav.id = 'topbar';
    nav.setAttribute('data-woniya-topbar', 'true');

    var wrap = document.createElement('div');
    wrap.className = 'wrap';

    var brand = document.createElement('a');
    brand.className = 'brand';
    brand.id = 'brandLink';
    setBrandState(brand, options, options.compact !== true && !hasOwn(options, 'brandDisabled') && !hasOwn(options, 'brandHref'), options.compact === true);

    var actions = document.createElement('div');
    actions.className = 'topbar-actions';
    syncActions(actions, options);

    wrap.appendChild(brand);
    wrap.appendChild(actions);
    nav.appendChild(wrap);

    document.body.insertBefore(nav, document.body.firstChild);
    return nav;
  }

  function updateBrand(options){
    options = options || {};
    var nav = document.getElementById('topbar');
    if (!isManagedTopbar(nav)) return null;
    var brand = nav && nav.querySelector('#brandLink');
    if (!brand) return null;
    var nextOptions = {
      centerName: hasOwn(options, 'centerName') ? options.centerName : brand.textContent,
      brandHref: hasOwn(options, 'brandHref') ? options.brandHref : '',
      brandDisabled: options.brandDisabled
    };
    setBrandState(brand, nextOptions, false, true);
    return nav;
  }

  function readTarget(search, previewIds){
    var params = new URLSearchParams(search || '');
    var allowed = previewIds || ['sunshine','carnival','forest','gallery'];
    var reviewToken = (params.get('review_token') || '').trim();
    var slug = reviewToken ? '' : (params.get('slug') || '').trim();
    var previewCenter = (reviewToken || slug) ? '' : (params.get('preview_center') || '').trim();
    var preview = (reviewToken || slug || previewCenter) ? '' : (params.get('preview') || '').trim().toLowerCase();
    if (preview && allowed.indexOf(preview) < 0) preview = '';
    if (reviewToken) return { mode:'review_token', value:reviewToken };
    if (slug) return { mode:'slug', value:slug };
    if (previewCenter) return { mode:'preview_center', value:previewCenter };
    if (preview) return { mode:'preview', value:preview };
    return { mode:'slug', value:'' };
  }

  function buildUrl(file, target, fallbackSlug){
    target = target || {};
    var value = target.value || (target.mode === 'slug' ? fallbackSlug : '');
    if (!value) return file;
    return file + '?' + encodeURIComponent(target.mode || 'slug') + '=' + encodeURIComponent(value);
  }

  function bindMenu(options){
    options = options || {};
    var button = options.button || document.getElementById('menuBtn');
    var panel = options.panel || document.getElementById('menuPanel');
    if (!button || !panel || button.dataset.menuBound === 'true') return;
    button.dataset.menuBound = 'true';

    function closeMenu(returnFocus){
      button.classList.remove('open');
      panel.classList.remove('open');
      button.setAttribute('aria-expanded','false');
      if (returnFocus) button.focus();
    }

    button.addEventListener('click', function(){
      var open = panel.classList.toggle('open');
      button.classList.toggle('open', open);
      button.setAttribute('aria-expanded', open ? 'true' : 'false');
      if (open) {
        window.setTimeout(function(){
          var firstLink = panel.querySelector('a[href]');
          if (firstLink) firstLink.focus();
        }, 0);
      }
    });
    panel.addEventListener('click', function(event){
      if (event.target.closest('a')) closeMenu(false);
    });
    document.addEventListener('click', function(event){
      if (!panel.contains(event.target) && !button.contains(event.target)) closeMenu(false);
    });
    document.addEventListener('keydown', function(event){
      if (event.key === 'Escape' && panel.classList.contains('open')) {
        event.preventDefault();
        closeMenu(true);
      }
    });
  }

  return {
    init: init,
    updateBrand: updateBrand,
    readTarget: readTarget,
    buildUrl: buildUrl,
    bindMenu: bindMenu
  };
})();
