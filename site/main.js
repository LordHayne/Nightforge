// The DE/EN switch and the copy button. The head script has already picked the first language.
(function () {
  var root = document.documentElement;
  var titles = {
    de: 'Nightforge – Deine Spiele auf dem Mac',
    en: 'Nightforge – Your games on your Mac'
  };
  var descriptions = {
    de: 'Nightforge ist ein kostenloser Spiele-Launcher für Macs mit Apple-Chip: Steam- und Epic-Spiele an einem Ort, Mac-Versionen zuerst, Windows-Spiele scharf und flüssig, ganz von selbst.',
    en: 'Nightforge is a free game launcher for Apple silicon Macs: Steam and Epic games in one place, Mac versions first, Windows games sharp and smooth by themselves.'
  };

  function apply(lang) {
    root.setAttribute('data-lang', lang);
    root.lang = lang;
    document.title = titles[lang];
    var meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute('content', descriptions[lang]);
    document.querySelectorAll('[data-set-lang]').forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.getAttribute('data-set-lang') === lang));
    });  }

  apply(root.getAttribute('data-lang') === 'de' ? 'de' : 'en');

  document.querySelectorAll('[data-set-lang]').forEach(function (button) {
    button.addEventListener('click', function () {
      var lang = button.getAttribute('data-set-lang');
      apply(lang);
      try { localStorage.setItem('nf-lang', lang); } catch (e) {}
    });
  });

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
