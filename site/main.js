// The DE/EN switch, the copy button and the fade-in. The head script has already picked the first
// language and decided whether sections may fade in (not with reduced motion).
(function () {
  var root = document.documentElement;

  // Each section fades up once when it comes into view; nothing moves after that.
  if (root.classList.contains('reveals')) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    document.querySelectorAll('.reveal').forEach(function (el) { observer.observe(el); });
  }
  var titles = {
    de: 'Nightforge – Deine Spiele auf dem Mac',
    en: 'Nightforge – Your games on your Mac'
  };
  var descriptions = {
    de: 'Nightforge ist ein kostenloser Spiele-Launcher für Macs mit Apple-Chip: Spiele von Steam, Epic und GOG an einem Ort, Mac-Versionen zuerst, Windows-Spiele scharf und flüssig, ganz von selbst.',
    en: 'Nightforge is a free game launcher for Apple silicon Macs: Steam, Epic and GOG games in one place, Mac versions first, Windows games sharp and smooth by themselves.'
  };

  function apply(lang) {
    root.setAttribute('data-lang', lang);
    root.lang = lang;
    document.title = titles[lang];
    var meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute('content', descriptions[lang]);
    document.querySelectorAll('[data-set-lang]').forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.getAttribute('data-set-lang') === lang));
    });
  }

  apply(root.getAttribute('data-lang') === 'de' ? 'de' : 'en');

  document.querySelectorAll('[data-set-lang]').forEach(function (button) {
    button.addEventListener('click', function () {
      var lang = button.getAttribute('data-set-lang');
      apply(lang);
      try { localStorage.setItem('nf-lang', lang); } catch (e) {}
    });
  });

  // The download buttons fetch the newest DMG straight away, and the line under them names its version.
  // Without an answer from GitHub everything stays as written: the buttons open the release page.
  var dmgLinks = document.querySelectorAll('[data-dmg]');
  if (dmgLinks.length && window.fetch) {
    fetch('https://api.github.com/repos/LordHayne/Nightforge/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (response) { return response.ok ? response.json() : null; })
      .then(function (release) {
        var dmg = release && (release.assets || []).filter(function (asset) { return /\.dmg$/.test(asset.name); })[0];
        if (!dmg) return;
        dmgLinks.forEach(function (link) {
          link.href = dmg.browser_download_url;
          // At the top, the download starts and the page goes on to what comes next: opening it.
          if (link.getAttribute('data-dmg') === 'show-install') {
            link.addEventListener('click', function () {
              var install = document.getElementById('install');
              var still = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
              if (install) install.scrollIntoView({ behavior: still ? 'auto' : 'smooth' });
            });
          }
        });
        var version = String(release.tag_name || '').replace(/^v/, '');
        var megabytes = (dmg.size / 1e6).toFixed(1);
        document.querySelectorAll('[data-release-version]').forEach(function (el) { if (version) el.textContent = version; });
        document.querySelectorAll('[data-release-size]').forEach(function (el) {
          var de = el.closest('[lang]') && el.closest('[lang]').getAttribute('lang') === 'de';
          el.textContent = de ? megabytes.replace('.', ',') : megabytes;
        });
      })
      .catch(function () {});
  }

  document.querySelectorAll('[data-copy]').forEach(function (button) {
    button.addEventListener('click', function () {
      var text = document.getElementById(button.getAttribute('data-copy')).textContent.trim();
      var done = function () {
        button.classList.add('done');
        setTimeout(function () { button.classList.remove('done'); }, 1800);
      };
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done, function () { fallback(text); done(); });
      } else {
        fallback(text);
        done();
      }
    });
  });

  // Older browsers and plain http: copy through a hidden text field.
  function fallback(text) {
    var field = document.createElement('textarea');
    field.value = text;
    field.setAttribute('readonly', '');
    field.style.position = 'fixed';
    field.style.opacity = '0';
    document.body.appendChild(field);
    field.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(field);
  }
})();
