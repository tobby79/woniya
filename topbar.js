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
      '.topbar-actions .menu-btn{visibility:visible}';
    document.head.appendChild(style);
  }

  var HOME_ICON_SVG =
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M3 9.5L12 3l9 6.5V20a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V9.5z"/>' +
      '<polyline points="9 21 9 12 15 12 15 21"/>' +
    '</svg>';

  function init(options){
    options = options || {};
    var centerName = options.centerName || '원이야';

    ensureStyle();

    var nav = document.createElement('nav');
    nav.className = 'topbar';
    nav.id = 'topbar';

    var wrap = document.createElement('div');
    wrap.className = 'wrap';

    var brand = document.createElement('a');
    brand.className = 'brand';
    brand.id = 'brandLink';
    brand.href = '#top';
    brand.textContent = centerName;

    var actions = document.createElement('div');
    actions.className = 'topbar-actions';

    var home = document.createElement('a');
    home.className = 'topbar-home';
    home.href = 'index.html';
    home.setAttribute('aria-label', '검색으로');
    home.innerHTML = HOME_ICON_SVG;
    actions.appendChild(home);

    var menuBtn = document.getElementById('menuBtn');
    if (menuBtn) actions.appendChild(menuBtn);

    wrap.appendChild(brand);
    wrap.appendChild(actions);
    nav.appendChild(wrap);

    document.body.insertBefore(nav, document.body.firstChild);
    return nav;
  }

  return { init: init };
})();
