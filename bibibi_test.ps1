<#
  bibibi_test — повне тестування ноутбука (Windows 10 / 11)
  https://github.com/w00o-o00w/bibibi_test

  Запуск: bibibi_test.bat (сам попросить права адміністратора)
     або: PowerShell від адміністратора → команда з README.

  Що робить: тільки ЧИТАЄ інформацію про залізо і систему, навантажує процесор,
  пише і видаляє тимчасовий файл для тесту швидкості диска, зберігає звіт на робочий стіл.
  Нічого не встановлює, не змінює налаштувань і нічого не відправляє в інтернет.

  Параметри (необов'язкові):
    -CpuSeconds 300   тривалість навантаження процесора, с
    -DiskTestMB 2048  розмір тесту швидкості диска, МБ
    -NoBrowser        не відкривати браузер (тільки автоматичні тести)
#>
param(
    [int]$CpuSeconds = 300,
    [int]$DiskTestMB = 2048,
    [switch]$NoBrowser
)

$BibibiVersion = '1.0.0'
$ErrorActionPreference = 'Stop'

# ============================================================== шаблон звіту
$Template = @'
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>bibibi_test — звіт</title>
<style>
:root{
  --bg:#f3f4f7;--card:#fff;--fg:#1b1f27;--mut:#646b78;--line:#e3e6eb;
  --fail:#d93025;--fail-bg:#fdecea;--warn:#e8710a;--warn-bg:#fef3e6;
  --ok:#188038;--ok-bg:#e7f4eb;--skip:#6f7682;--skip-bg:#eef0f3;--acc:#2f6fed;
  --dk:#12161d;--dk2:#1c222c;--dk3:#2a313d;--dkt:#e9ecf1;--dkm:#98a1b0;
}
*{box-sizing:border-box}
html,body{margin:0}
body{background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",-apple-system,BlinkMacSystemFont,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;padding-bottom:96px}
.wrap{max-width:1040px;margin:0 auto;padding:24px 16px}
.hero{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px 24px;display:grid;grid-template-columns:1fr auto;gap:18px;border-top:6px solid var(--skip)}
.hero.v-fail{border-top-color:var(--fail)}.hero.v-warn{border-top-color:var(--warn)}.hero.v-ok{border-top-color:var(--ok)}
.hero h1{margin:0;font-size:26px;letter-spacing:-.01em;word-break:break-word}
.hero .sub{color:var(--mut);margin-top:2px}
.facts{display:flex;flex-wrap:wrap;gap:4px 18px;margin-top:12px;font-size:13px;color:var(--mut)}
.facts b{color:var(--fg);font-weight:600}
.verdict{text-align:right}
.pill{display:inline-block;padding:10px 16px;border-radius:12px;font-weight:700;color:#fff;background:var(--skip);font-size:15px;letter-spacing:.01em}
.v-fail .pill{background:var(--fail)}.v-warn .pill{background:var(--warn)}.v-ok .pill{background:var(--ok)}
.counts{display:flex;gap:6px;justify-content:flex-end;margin-top:10px;flex-wrap:wrap}
.cnt{font-size:12px;font-weight:600;padding:3px 9px;border-radius:999px}
.cnt.fail{background:var(--fail-bg);color:var(--fail)}.cnt.warn{background:var(--warn-bg);color:var(--warn)}
.cnt.ok{background:var(--ok-bg);color:var(--ok)}.cnt.skip{background:var(--skip-bg);color:var(--skip)}
.stamp{margin-top:8px;font-size:12px;color:var(--mut)}
@media(max-width:680px){.hero{grid-template-columns:1fr}.verdict{text-align:left}.counts{justify-content:flex-start}}

.manual{margin-top:18px;background:var(--dk);color:var(--dkt);border-radius:16px;padding:20px 22px}
.manual h2{margin:0 0 4px;font-size:18px}
.manual>p{margin:0 0 14px;color:var(--dkm);font-size:14px}
.mgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px}
.mcard{background:var(--dk2);border:1px solid var(--dk3);border-radius:12px;padding:14px;display:flex;flex-direction:column;gap:8px}
.mcard .t{font-weight:700;font-size:16px}
.mcard .d{font-size:13px;color:var(--dkm);flex:1}
.st{font-size:12px;font-weight:700}
.st.pending{color:var(--dkm)}.st.ok{color:#5fd38a}.st.warn{color:#ffad5c}.st.fail{color:#ff7a70}.st.skip{color:#b6bcc7}
.mactions{margin-top:14px;display:flex;gap:8px;flex-wrap:wrap}
.btn{font:inherit;font-weight:600;border:0;border-radius:10px;padding:9px 14px;cursor:pointer;background:var(--acc);color:#fff}
.btn:hover{filter:brightness(1.1)}
.btn.ghost{background:var(--dk3);color:var(--dkt)}
.btn.ok{background:var(--ok)}.btn.fail{background:var(--fail)}.btn.skip{background:#596070}
.btn.big{padding:12px 20px;font-size:16px}

.block{margin-top:18px;background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden}
.block>summary{list-style:none;cursor:pointer;padding:14px 18px;display:flex;align-items:center;gap:10px;font-weight:700;font-size:16px}
.block>summary::-webkit-details-marker{display:none}
.block .dot{width:12px;height:12px;border-radius:50%;flex:none;background:var(--skip)}
.block .n{margin-left:auto;font-size:13px;font-weight:600;opacity:.85}
.block.fail>summary{background:var(--fail-bg);color:var(--fail)}.block.fail .dot{background:var(--fail)}
.block.warn>summary{background:var(--warn-bg);color:var(--warn)}.block.warn .dot{background:var(--warn)}
.block.ok>summary{background:var(--ok-bg);color:var(--ok)}.block.ok .dot{background:var(--ok)}
.block.skip>summary{background:var(--skip-bg);color:var(--skip)}
.block.specs>summary{color:var(--fg)}
.item{display:grid;grid-template-columns:240px 1fr;gap:4px 18px;padding:10px 18px;border-top:1px solid var(--line)}
.item .c{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.04em}
.item .tt{font-weight:600}
.item .v{color:#323946;word-break:break-word;align-self:center}
.empty{padding:12px 18px;color:var(--mut);border-top:1px solid var(--line)}
.specs table{width:100%;border-collapse:collapse}
.specs td{padding:8px 18px;border-top:1px solid var(--line);vertical-align:top;word-break:break-word}
.specs td:first-child{width:32%;color:var(--mut)}
@media(max-width:680px){.item{grid-template-columns:1fr}.specs td:first-child{width:40%}}
footer{color:var(--mut);font-size:12px;margin-top:22px;text-align:center}

.savebar{position:fixed;left:0;right:0;bottom:0;background:var(--dk);color:var(--dkt);padding:12px 16px;display:flex;align-items:center;gap:14px;justify-content:center;flex-wrap:wrap;box-shadow:0 -6px 24px rgba(0,0,0,.18);z-index:20}
.savebar .fn{font-size:13px;color:var(--dkm);word-break:break-all}
.toast{position:fixed;left:50%;bottom:92px;transform:translateX(-50%);background:#1d6b3c;color:#fff;padding:12px 18px;border-radius:12px;z-index:30;max-width:92vw;box-shadow:0 8px 24px rgba(0,0,0,.25);font-weight:600}

.stage{position:fixed;inset:0;background:var(--dk);color:var(--dkt);z-index:40;display:flex;flex-direction:column}
.stage[hidden]{display:none}
.stage>header{padding:16px 20px;border-bottom:1px solid var(--dk3)}
.stage h2{margin:0;font-size:20px}
.stage .hint{margin:4px 0 0;color:var(--dkm);font-size:14px;max-width:960px}
.stage .body{flex:1;overflow:auto;padding:20px}
.stage .foot{padding:12px 20px;border-top:1px solid var(--dk3);display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.stage .foot input{flex:1;min-width:220px;font:inherit;padding:10px 12px;border-radius:10px;border:1px solid var(--dk3);background:var(--dk2);color:var(--dkt)}
.auto{font-size:13px;color:var(--dkm);width:100%}
.note{color:var(--dkm);font-size:14px;margin:12px 0 0}

.kb{display:flex;flex-direction:column;gap:6px;max-width:1040px;margin:0 auto;user-select:none}
.krow{display:flex;gap:6px}
.k{height:48px;flex:1 1 0;min-width:0;background:var(--dk3);border:1px solid #384152;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:12px;color:#b3bbc8;overflow:hidden;white-space:nowrap;padding:0 2px}
.k.done{background:#1c6b3c;color:#e0ffea;border-color:#2b9a59}
.k.down{background:#ffd34d;color:#111;border-color:#ffd34d}
.kopt{max-width:1040px;margin:16px auto 0}
.kopt h3{font-size:13px;color:var(--dkm);margin:0 0 6px;font-weight:600}
.kopt .krow{flex-wrap:wrap}.kopt .k{flex:0 0 auto;padding:0 12px}
.kstat{text-align:center;margin-top:14px;color:var(--dkm)}
.kstat b{color:#fff}

.tp{position:relative;max-width:1040px;margin:0 auto;height:min(52vh,460px);border-radius:14px;overflow:hidden;border:1px solid var(--dk3);touch-action:none;cursor:crosshair}
.tpgrid{position:absolute;inset:0;display:grid;grid-template-columns:repeat(8,1fr);grid-template-rows:repeat(5,1fr)}
.tpgrid div{border:1px solid #1a1f28;background:#171c25;transition:background .15s}
.tpgrid div.on{background:#1c5a36}
.tp canvas{position:absolute;inset:0;width:100%;height:100%}
.ind{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:14px}
.ind span{padding:7px 12px;border-radius:9px;background:var(--dk3);color:var(--dkm);font-size:13px}
.ind span.on{background:#2b9a59;color:#fff}
.sgrid{display:flex;flex-wrap:wrap;gap:10px}

#fs{position:fixed;inset:0;z-index:60;cursor:none}
#fs[hidden]{display:none}
#fsLabel{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);font:12px system-ui,sans-serif;color:#888;mix-blend-mode:difference;z-index:61}
@media print{.savebar,.manual,.stage,.toast{display:none!important}body{background:#fff;padding:0}.block{break-inside:avoid}}
</style>
</head>
<body>
<div id="app"></div>

<div id="stage" class="stage" hidden>
  <header><h2 id="stTitle"></h2><p class="hint" id="stHint"></p></header>
  <div class="body" id="stBody"></div>
  <div class="foot">
    <div class="auto" id="stAuto"></div>
    <input id="stComment" type="text" placeholder="Коментар (необов'язково): що саме не так">
    <button class="btn ok" data-v="ok" type="button">Працює</button>
    <button class="btn fail" data-v="fail" type="button">Проблема</button>
    <button class="btn skip" data-v="skip" type="button">Пропустити</button>
  </div>
</div>
<div id="fs" hidden><div id="fsLabel"></div></div>

<script id="bibibi-data" type="application/json">__BIBIBI_DATA__</script>
<script>
(function () {
  'use strict';
  var ORIGINAL = '<!DOCTYPE html>\n' + document.documentElement.outerHTML;
  var DATA = null;
  try { DATA = JSON.parse(document.getElementById('bibibi-data').textContent); } catch (e) { DATA = null; }
  if (!DATA || typeof DATA !== 'object') DATA = demoData();
  DATA.meta = DATA.meta || {}; DATA.results = DATA.results || []; DATA.specs = DATA.specs || []; DATA.manual = DATA.manual || {};
  var FINAL = DATA.final === true;
  var IS_MAC = DATA.meta.platform ? DATA.meta.platform === 'macos' : /Mac/i.test(navigator.platform);

  var ORDER = ['fail', 'warn', 'ok', 'skip'];
  var TITLES = { fail: 'Критично', warn: 'Зауваження', ok: 'Норма', skip: 'Не вдалося перевірити' };
  var SHORT = { fail: 'Критично', warn: 'Зауваження', ok: 'Норма', skip: 'Не перевірено' };
  var MSTATE = { ok: 'Працює', fail: 'Проблема', skip: 'Пропущено', warn: 'Зауваження' };
  var MANUAL = [
    { id: 'screen', name: 'Екран', desc: 'Кольори на весь екран: биті пікселі, засвіти, смуги.' },
    { id: 'sound', name: 'Динаміки', desc: 'Лівий і правий канал, свіп частот, без хрипу.' },
    { id: 'keyboard', name: 'Клавіатура', desc: 'Натиснути всі основні клавіші.' },
    { id: 'touchpad', name: 'Тачпад', desc: 'Усі зони сенсора, кліки, прокрутка, жести.' }
  ];

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // ---------------------------------------------------------------- дані
  function manualItems() {
    return MANUAL.map(function (m) {
      var r = DATA.manual[m.id];
      if (r && r.status) {
        return { cat: 'Ручні тести', test: m.name, status: r.status,
          value: (r.value || '') + (r.comment ? ' — коментар: ' + r.comment : '') };
      }
      return { cat: 'Ручні тести', test: m.name, status: 'skip', value: FINAL ? 'не перевірялось' : 'ще не перевірено' };
    });
  }
  function allItems() { return DATA.results.concat(manualItems()); }
  function summary() {
    var c = { fail: 0, warn: 0, ok: 0, skip: 0 };
    allItems().forEach(function (i) { if (c[i.status] != null) c[i.status]++; });
    var v = c.fail ? 'fail' : (c.warn ? 'warn' : 'ok');
    return { cls: v, verdict: { fail: 'Є КРИТИЧНІ ПРОБЛЕМИ', warn: 'Є ЗАУВАЖЕННЯ', ok: 'ВСЕ ДОБРЕ' }[v],
      fail: c.fail, warn: c.warn, ok: c.ok, skip: c.skip };
  }

  // ---------------------------------------------------------------- звіт
  function render() {
    var m = DATA.meta, s = summary(), h = '<div class="wrap">';
    h += '<section class="hero v-' + s.cls + '"><div>';
    h += '<h1>' + esc(m.hostname || 'Без назви') + '</h1>';
    h += '<div class="sub">' + esc(m.model || '') + '</div><div class="facts">';
    h += fact('S/N', m.serial || 'не вказано') + fact('Дата', m.datetime || m.date) + fact('ОС', m.os) +
      fact('Тривалість', m.duration ? m.duration + ' хв' : '');
    h += '</div></div><div class="verdict"><span class="pill">' + esc(s.verdict) + '</span><div class="counts">';
    ORDER.forEach(function (st) { h += '<span class="cnt ' + st + '">' + SHORT[st] + ': ' + s[st] + '</span>'; });
    h += '</div><div class="stamp">' + (FINAL ? 'Фінальний звіт' : 'Проміжний звіт: пройдіть ручні тести і натисніть «Зберегти звіт»') + '</div></div></section>';
    if (!FINAL) h += manualPanel();
    ORDER.forEach(function (st) { h += block(st); });
    h += specsBlock();
    h += '<footer>bibibi_test ' + esc(DATA.version || '') + ' · звіт створено локально на цьому ПК і нікуди не відправлявся</footer></div>';
    if (!FINAL) {
      h += '<div class="savebar"><span class="fn">Файл: ' + esc(m.filename || '') + '</span>' +
        '<button class="btn big ok" id="saveBtn" type="button">Зберегти звіт</button></div>';
    }
    $('app').innerHTML = h;
    bindApp();
  }
  function fact(k, v) { return v ? '<span>' + esc(k) + ': <b>' + esc(v) + '</b></span>' : ''; }
  function block(st) {
    var items = allItems().filter(function (i) { return i.status === st; });
    var h = '<details class="block ' + st + '"' + (st === 'ok' && items.length > 12 ? '' : ' open') + '><summary><span class="dot"></span>' +
      TITLES[st] + '<span class="n">' + items.length + '</span></summary>';
    if (!items.length) h += '<div class="empty">Немає</div>';
    items.forEach(function (i) {
      h += '<div class="item"><div><div class="c">' + esc(i.cat) + '</div><div class="tt">' + esc(i.test) +
        '</div></div><div class="v">' + esc(i.value) + '</div></div>';
    });
    return h + '</details>';
  }
  function specsBlock() {
    var h = '<details class="block specs" open><summary><span class="dot"></span>Характеристики<span class="n">' +
      DATA.specs.length + '</span></summary><table>';
    DATA.specs.forEach(function (s) { h += '<tr><td>' + esc(s.k) + '</td><td>' + esc(s.v) + '</td></tr>'; });
    return h + '</table></details>';
  }
  function manualPanel() {
    var h = '<section class="manual"><h2>Ручні тести</h2><p>Ці перевірки робить людина. Після кожної натисніть «Працює», «Проблема» або «Пропустити».</p><div class="mgrid">';
    MANUAL.forEach(function (m) {
      var r = DATA.manual[m.id], st = r && r.status ? r.status : 'pending';
      h += '<div class="mcard"><div class="t">' + m.name + '</div><div class="d">' + m.desc + '</div>' +
        '<div class="st ' + st + '">' + (st === 'pending' ? 'Не перевірено' : MSTATE[st]) + '</div>' +
        '<button class="btn ghost" type="button" data-test="' + m.id + '">' + (st === 'pending' ? 'Почати' : 'Повторити') + '</button></div>';
    });
    return h + '</div><div class="mactions"><button class="btn big" id="wizardBtn" type="button">Пройти всі по черзі</button></div></section>';
  }
  function bindApp() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-test]'), function (b) {
      b.addEventListener('click', function () { wizard = false; openTest(b.getAttribute('data-test')); });
    });
    if ($('wizardBtn')) $('wizardBtn').addEventListener('click', function () {
      wizard = true;
      var next = MANUAL.filter(function (m) { return !(DATA.manual[m.id] && DATA.manual[m.id].status); })[0] || MANUAL[0];
      openTest(next.id);
    });
    if ($('saveBtn')) $('saveBtn').addEventListener('click', save);
  }

  // ---------------------------------------------------------------- ручні тести: каркас
  var current = null, wizard = false, tests = {};
  function openTest(id) {
    current = id;
    var t = tests[id], m = MANUAL.filter(function (x) { return x.id === id; })[0];
    $('stTitle').textContent = m.name;
    $('stHint').textContent = t.hint();
    $('stBody').innerHTML = '';
    $('stComment').value = (DATA.manual[id] && DATA.manual[id].comment) || '';
    $('stage').hidden = false;
    document.body.style.overflow = 'hidden';
    t.open($('stBody'));
    updateAuto();
  }
  function updateAuto() { if (current) $('stAuto').textContent = tests[current].auto(); }
  function finish(v) {
    var id = current, t = tests[id];
    DATA.manual[id] = { status: v, value: v === 'skip' ? 'пропущено' : t.auto(), comment: $('stComment').value.trim() };
    t.close();
    current = null;
    $('stage').hidden = true;
    document.body.style.overflow = '';
    render();
    if (wizard) {
      var idx = MANUAL.map(function (m) { return m.id; }).indexOf(id);
      if (idx >= 0 && idx < MANUAL.length - 1) { openTest(MANUAL[idx + 1].id); return; }
      wizard = false;
    }
    window.scrollTo(0, 0);
  }
  Array.prototype.forEach.call(document.querySelectorAll('#stage .foot [data-v]'), function (b) {
    b.addEventListener('click', function () { finish(b.getAttribute('data-v')); });
  });

  // ---------------------------------------------------------------- екран
  var SLIDES = [
    ['#000', 'чорний'], ['#fff', 'білий'], ['#f00', 'червоний'], ['#0f0', 'зелений'], ['#00f', 'синій'],
    ['#808080', 'сірий'], ['#ff0', 'жовтий'], ['#0ff', 'блакитний'], ['#f0f', 'пурпурний'],
    ['linear-gradient(90deg,#000,#fff)', 'градієнт'],
    ['repeating-linear-gradient(0deg,#000 0 1px,#fff 1px 2px)', 'тонкі смужки']
  ];
  var slide = 0, seen = 0;
  function paintSlide() {
    $('fs').style.background = SLIDES[slide][0];
    $('fsLabel').textContent = (slide + 1) + ' / ' + SLIDES.length + ' · ' + SLIDES[slide][1] + ' · клік — далі, Esc — вихід';
    seen = Math.max(seen, slide + 1);
  }
  function startSlides() {
    slide = 0; paintSlide(); $('fs').hidden = false;
    var el = document.documentElement;
    var rq = el.requestFullscreen || el.webkitRequestFullscreen;
    if (rq) { try { var p = rq.call(el); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
  }
  function nextSlide() { slide++; if (slide >= SLIDES.length) endSlides(); else paintSlide(); }
  function endSlides() {
    $('fs').hidden = true;
    var fe = document.fullscreenElement || document.webkitFullscreenElement;
    var ex = document.exitFullscreen || document.webkitExitFullscreen;
    if (fe && ex) { try { var p = ex.call(document); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
    updateAuto();
  }
  $('fs').addEventListener('click', nextSlide);
  function onFsChange() {
    if (!(document.fullscreenElement || document.webkitFullscreenElement) && !$('fs').hidden) endSlides();
  }
  document.addEventListener('fullscreenchange', onFsChange);
  document.addEventListener('webkitfullscreenchange', onFsChange);
  tests.screen = {
    hint: function () { return 'Екран заливається кольорами на весь розмір. Клік або будь-яка клавіша — наступний колір, Esc — вихід. На чорному шукайте засвіти по краях і світлі точки, на білому та кольорових — темні або кольорові точки (биті пікселі), на сірому та градієнті — плями й смуги.'; },
    open: function (b) {
      seen = 0;
      b.innerHTML = '<button class="btn big" type="button" id="scrGo">Показати кольори на весь екран</button><p class="note">Кольорів: ' + SLIDES.length + '. Можна пройти кілька разів.</p>';
      $('scrGo').addEventListener('click', startSlides);
    },
    auto: function () { return seen ? 'переглянуто кольорів: ' + seen + ' з ' + SLIDES.length : 'кольори ще не показувались'; },
    close: function () { if (!$('fs').hidden) endSlides(); }
  };

  // ---------------------------------------------------------------- звук
  var ac = null, played = {}, osc = [];
  function actx() {
    if (!ac) { var C = window.AudioContext || window.webkitAudioContext; ac = new C(); }
    if (ac.state === 'suspended') ac.resume();
    return ac;
  }
  function stopSound() { osc.forEach(function (o) { try { o.stop(); } catch (e) {} }); osc = []; }
  function tone(pan, key) {
    stopSound();
    var a = actx(), o = a.createOscillator(), g = a.createGain(), t = a.currentTime, out = g;
    o.frequency.value = 440;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.35, t + 0.05);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 1.5);
    o.connect(g);
    if (a.createStereoPanner) { var p = a.createStereoPanner(); p.pan.value = pan; g.connect(p); out = p; }
    out.connect(a.destination);
    o.start(t); o.stop(t + 1.6); osc.push(o);
    played[key] = true; updateAuto();
  }
  function sweep() {
    stopSound();
    var a = actx(), o = a.createOscillator(), g = a.createGain(), t = a.currentTime;
    o.frequency.setValueAtTime(60, t);
    o.frequency.exponentialRampToValueAtTime(12000, t + 8);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.3, t + 0.2);
    g.gain.setValueAtTime(0.3, t + 7.8);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 8);
    o.connect(g); g.connect(a.destination);
    o.start(t); o.stop(t + 8.1); osc.push(o);
    played.sweep = true; updateAuto();
  }
  tests.sound = {
    hint: function () { return 'Поставте гучність приблизно на 70%. Звук «Лівий» має йти лише з лівого динаміка, «Правий» — лише з правого. На свіпі (від низьких до високих частот) слухайте, чи немає хрипу, дребезжання корпусу або провалів звуку.'; },
    open: function (b) {
      played = {};
      b.innerHTML = '<div class="sgrid">' +
        '<button class="btn big" type="button" id="sL">◀ Лівий</button>' +
        '<button class="btn big" type="button" id="sR">Правий ▶</button>' +
        '<button class="btn big" type="button" id="sB">Обидва</button>' +
        '<button class="btn big ghost" type="button" id="sS">Свіп 60 Гц → 12 кГц</button>' +
        '<button class="btn big ghost" type="button" id="sX">Стоп</button></div>' +
        '<p class="note">Якщо є роз\'єм для навушників — підключіть їх і повторіть.</p>';
      $('sL').addEventListener('click', function () { tone(-1, 'left'); });
      $('sR').addEventListener('click', function () { tone(1, 'right'); });
      $('sB').addEventListener('click', function () { tone(0, 'both'); });
      $('sS').addEventListener('click', sweep);
      $('sX').addEventListener('click', stopSound);
    },
    auto: function () {
      var n = { left: 'лівий', right: 'правий', both: 'обидва', sweep: 'свіп' }, done = [];
      Object.keys(n).forEach(function (k) { if (played[k]) done.push(n[k]); });
      return done.length ? 'відтворено: ' + done.join(', ') : 'звук ще не відтворювався';
    },
    close: stopSound
  };

  // ---------------------------------------------------------------- клавіатура
  var KL = {
    Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';',
    Quote: "'", Comma: ',', Period: '.', Slash: '/', Escape: 'Esc', Backspace: IS_MAC ? 'delete' : 'Backspace',
    Tab: 'Tab', CapsLock: 'Caps', Enter: IS_MAC ? 'return' : 'Enter', ShiftLeft: 'Shift', ShiftRight: 'Shift',
    ControlLeft: IS_MAC ? 'control' : 'Ctrl', ControlRight: 'Ctrl', MetaLeft: IS_MAC ? '⌘ cmd' : 'Win',
    MetaRight: '⌘ cmd', AltLeft: IS_MAC ? '⌥ option' : 'Alt', AltRight: IS_MAC ? '⌥ option' : 'Alt',
    Space: 'Пробіл', ContextMenu: 'Меню', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓',
    Delete: 'Del', Insert: 'Ins', Home: 'Home', End: 'End', PageUp: 'PgUp', PageDown: 'PgDn',
    PrintScreen: 'PrtSc', IntlBackslash: '\\ (ISO)', NumLock: 'NumLk', ScrollLock: 'ScrLk', Pause: 'Pause'
  };
  function lbl(c) { return KL[c] || c.replace(/^Key/, '').replace(/^Digit/, '').replace(/^Numpad/, 'Num '); }
  function seq(s) { return s.split('').map(function (c) { return (/\d/.test(c) ? 'Digit' : 'Key') + c; }); }
  var FK = []; for (var fi = 1; fi <= 12; fi++) FK.push('F' + fi);
  var ROWS_MID = [
    ['Backquote'].concat(seq('1234567890'), ['Minus', 'Equal', ['Backspace', 2]]),
    [['Tab', 1.5]].concat(seq('QWERTYUIOP'), ['BracketLeft', 'BracketRight', ['Backslash', 1.5]]),
    [['CapsLock', 1.8]].concat(seq('ASDFGHJKL'), ['Semicolon', 'Quote', ['Enter', 2.2]]),
    [['ShiftLeft', 2.4]].concat(seq('ZXCVBNM'), ['Comma', 'Period', 'Slash', ['ShiftRight', 2.6]])
  ];
  var ROWS = IS_MAC
    ? [['Escape'].concat(FK)].concat(ROWS_MID, [['ControlLeft', 'AltLeft', ['MetaLeft', 1.4], ['Space', 6], ['MetaRight', 1.4], 'AltRight', 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowRight']])
    : [['Escape'].concat(FK, ['Delete'])].concat(ROWS_MID, [[['ControlLeft', 1.3], 'MetaLeft', 'AltLeft', ['Space', 6], 'AltRight', ['ControlRight', 1.3], 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowRight']]);
  var OPTIONAL = IS_MAC ? [] : ['PrintScreen', 'Insert', 'Home', 'End', 'PageUp', 'PageDown', 'ContextMenu'];
  var REQUIRED = [];
  ROWS.forEach(function (r) { r.forEach(function (k) { REQUIRED.push(Array.isArray(k) ? k[0] : k); }); });
  var kbEls = {}, kbDone = {};
  function kbBuild(b) {
    kbEls = {}; kbDone = {};
    var h = '<div class="kb">';
    ROWS.forEach(function (r) {
      h += '<div class="krow">';
      r.forEach(function (k) {
        var code = Array.isArray(k) ? k[0] : k, w = Array.isArray(k) ? k[1] : 1;
        h += '<div class="k" data-code="' + code + '" style="flex-grow:' + w + '">' + esc(lbl(code)) + '</div>';
      });
      h += '</div>';
    });
    h += '</div><div class="kopt"><h3>Додаткові (є не на всіх ноутбуках, не обов\'язкові)</h3><div class="krow" id="kExtra">';
    OPTIONAL.forEach(function (c) { h += '<div class="k" data-code="' + c + '">' + esc(lbl(c)) + '</div>'; });
    h += '</div></div><div class="kstat">Основні: <b id="kN">0</b> з <b>' + REQUIRED.length + '</b> · остання: <b id="kLast">—</b></div>' +
      '<p class="note" style="text-align:center"><button class="btn ghost" type="button" id="kReset">Скинути</button></p>';
    b.innerHTML = h;
    Array.prototype.forEach.call(b.querySelectorAll('.k'), function (el) { kbEls[el.getAttribute('data-code')] = el; });
    $('kReset').addEventListener('click', function () { kbBuild(b); updateAuto(); });
  }
  function kbEl(code) {
    if (!kbEls[code]) {
      var el = document.createElement('div');
      el.className = 'k'; el.textContent = lbl(code); el.setAttribute('data-code', code);
      $('kExtra').appendChild(el); kbEls[code] = el;
    }
    return kbEls[code];
  }
  function kbMark(code) {
    kbDone[code] = true;
    kbEl(code).classList.add('done');
    var n = REQUIRED.filter(function (c) { return kbDone[c]; }).length;
    $('kN').textContent = n;
    updateAuto();
  }
  function kbActive(e) {
    return current === 'keyboard' && $('fs').hidden && document.activeElement !== $('stComment') && e.code;
  }
  document.addEventListener('keydown', function (e) {
    if (!$('fs').hidden) { e.preventDefault(); if (e.key !== 'Escape') nextSlide(); else endSlides(); return; }
    if (!kbActive(e)) return;
    e.preventDefault();
    kbEl(e.code).classList.add('down');
    $('kLast').textContent = e.code + (e.key && e.key.length === 1 ? ' (' + e.key + ')' : '');
    kbMark(e.code);
  }, true);
  document.addEventListener('keyup', function (e) {
    if (!kbActive(e)) return;
    e.preventDefault();
    kbEl(e.code).classList.remove('down');
    if (!kbDone[e.code]) kbMark(e.code);   // PrintScreen у Windows приходить тільки як keyup
  }, true);
  window.addEventListener('blur', function () {
    Array.prototype.forEach.call(document.querySelectorAll('.k.down'), function (k) { k.classList.remove('down'); });
  });
  tests.keyboard = {
    hint: function () {
      return 'Натисніть по черзі всі клавіші: кожна має стати зеленою. Жовта — затиснута зараз; якщо клавіша світиться жовтим без натискання, вона залипає. Fn браузер не бачить — перевірте її через яскравість чи гучність. ' +
        (IS_MAC ? 'Не натискайте ⌘ разом з іншими клавішами (⌘W закриє вкладку). F1–F12 натискайте разом з fn.' : 'Клавіша Win відкриє меню «Пуск» — просто закрийте його.');
    },
    open: kbBuild,
    auto: function () {
      var miss = REQUIRED.filter(function (c) { return !kbDone[c]; });
      var extra = Object.keys(kbDone).filter(function (c) { return REQUIRED.indexOf(c) < 0; }).length;
      var s = miss.length ? 'не натиснуто ' + miss.length + ' з ' + REQUIRED.length + ': ' + miss.map(lbl).join(' ') : 'усі ' + REQUIRED.length + ' основних клавіш спрацювали';
      return s + (extra ? '; додаткових: ' + extra : '');
    },
    close: function () {}
  };

  // ---------------------------------------------------------------- тачпад
  var TP_COLS = 8, TP_ROWS = 5, tpCells = {}, tpFlags = {}, tpLast = null, tpCtx = null;
  var TP_IND = [['left', 'Лівий клік / тап'], ['right', 'Правий клік'], ['up', 'Прокрутка ↑'], ['down', 'Прокрутка ↓'],
    ['l', 'Прокрутка ←'], ['r', 'Прокрутка →'], ['zoom', 'Масштаб (зведення пальців)']];
  function tpFlag(k) { if (!tpFlags[k]) { tpFlags[k] = true; var s = document.querySelector('#tpInd [data-i="' + k + '"]'); if (s) s.classList.add('on'); updateAuto(); } }
  function tpOpen(b) {
    tpCells = {}; tpFlags = {}; tpLast = null;
    var h = '<div class="tp" id="tp"><div class="tpgrid" id="tpGrid">';
    for (var i = 0; i < TP_COLS * TP_ROWS; i++) h += '<div></div>';
    h += '</div><canvas id="tpC"></canvas></div><div class="ind" id="tpInd">';
    TP_IND.forEach(function (x) { h += '<span data-i="' + x[0] + '">' + x[1] + '</span>'; });
    h += '</div><div class="kstat">Зони сенсора: <b id="tpN">0</b> з ' + (TP_COLS * TP_ROWS) +
      '</div><p class="note" style="text-align:center"><button class="btn ghost" type="button" id="tpReset">Скинути</button></p>';
    b.innerHTML = h;
    var tp = $('tp'), c = $('tpC'), r = tp.getBoundingClientRect(), d = window.devicePixelRatio || 1;
    c.width = Math.round(r.width * d); c.height = Math.round(r.height * d);
    tpCtx = c.getContext('2d'); tpCtx.scale(d, d);
    var cells = $('tpGrid').children;
    tp.addEventListener('pointermove', function (e) {
      var rr = tp.getBoundingClientRect(), x = e.clientX - rr.left, y = e.clientY - rr.top;
      var col = Math.min(TP_COLS - 1, Math.max(0, Math.floor(x / rr.width * TP_COLS)));
      var row = Math.min(TP_ROWS - 1, Math.max(0, Math.floor(y / rr.height * TP_ROWS)));
      var idx = row * TP_COLS + col;
      if (!tpCells[idx]) { tpCells[idx] = true; cells[idx].className = 'on'; $('tpN').textContent = Object.keys(tpCells).length; updateAuto(); }
      if (tpLast) {
        tpCtx.strokeStyle = e.buttons ? '#ffd34d' : '#6aa8ff'; tpCtx.lineWidth = e.buttons ? 4 : 2; tpCtx.lineCap = 'round';
        tpCtx.beginPath(); tpCtx.moveTo(tpLast[0], tpLast[1]); tpCtx.lineTo(x, y); tpCtx.stroke();
      }
      tpLast = [x, y];
    });
    tp.addEventListener('pointerleave', function () { tpLast = null; });
    tp.addEventListener('mousedown', function (e) { if (e.button === 0) tpFlag('left'); if (e.button === 2) tpFlag('right'); e.preventDefault(); });
    tp.addEventListener('contextmenu', function (e) { e.preventDefault(); tpFlag('right'); });
    tp.addEventListener('wheel', function (e) {
      e.preventDefault();
      if (e.ctrlKey) { tpFlag('zoom'); return; }
      if (e.deltaY < 0) tpFlag('up'); if (e.deltaY > 0) tpFlag('down');
      if (e.deltaX < 0) tpFlag('l'); if (e.deltaX > 0) tpFlag('r');
    }, { passive: false });
    tp.addEventListener('gesturestart', function (e) { e.preventDefault(); });
    tp.addEventListener('gesturechange', function (e) { e.preventDefault(); tpFlag('zoom'); });
    $('tpReset').addEventListener('click', function () { tpOpen(b); updateAuto(); });
  }
  window.addEventListener('wheel', function (e) { if (current === 'touchpad' && e.ctrlKey) e.preventDefault(); }, { passive: false });
  tests.touchpad = {
    hint: function () { return 'Поводьте пальцем по всьому полю, поки всі клітинки не стануть зеленими: незафарбовані місця означають мертві зони сенсора. Лінія має бути плавною, без стрибків. Перевірте лівий і правий клік, тап, прокрутку двома пальцями в усі боки та зведення-розведення двох пальців.'; },
    open: tpOpen,
    auto: function () {
      var n = Object.keys(tpCells).length, all = TP_COLS * TP_ROWS;
      var ok = [], no = [];
      TP_IND.forEach(function (x) { (tpFlags[x[0]] ? ok : no).push(x[1].toLowerCase()); });
      return 'зони сенсора: ' + n + ' з ' + all + (ok.length ? '; працює: ' + ok.join(', ') : '') + (no.length ? '; не перевірено: ' + no.join(', ') : '');
    },
    close: function () {}
  };

  // ---------------------------------------------------------------- збереження
  function toast(msg) {
    var t = document.createElement('div'); t.className = 'toast'; t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 7000);
  }
  function save() {
    var pend = MANUAL.filter(function (m) { return !(DATA.manual[m.id] && DATA.manual[m.id].status); });
    if (pend.length && !confirm('Не пройдено ручні тести: ' + pend.map(function (m) { return m.name; }).join(', ') +
      '.\nВони потраплять у блок «Не вдалося перевірити».\n\nЗберегти звіт?')) return;
    var copy = JSON.parse(JSON.stringify(DATA));
    var s = summary();
    copy.final = true;
    copy.savedAt = new Date().toISOString();
    copy.summary = { verdict: s.verdict, fail: s.fail, warn: s.warn, ok: s.ok, skip: s.skip };
    var json = JSON.stringify(copy).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    var re = /(<script id="bibibi-data" type="application\/json">)[\s\S]*?(<\/script>)/;
    var html = ORIGINAL.replace(re, function (all, a, b) { return a + json + b; });
    var blob = new Blob([html], { type: 'text/html;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = DATA.meta.filename || 'bibibi_report.html';
    document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 5000);
    toast('Звіт збережено. Скрипт сам перенесе його на робочий стіл — дивіться в консоль.');
  }

  // ---------------------------------------------------------------- демо (коли сторінку відкрито без даних)
  function demoData() {
    return {
      version: 'demo', final: false,
      meta: { hostname: 'DEMO-PC', model: 'Демо-ноутбук', serial: 'DEMO123', os: 'демо', platform: '', datetime: new Date().toLocaleString('uk-UA'), duration: '0', filename: 'DEMO-PC - SN DEMO123.html' },
      results: [
        { cat: 'Батарея', test: 'Стан батареї', value: '41% від заводської ємності', status: 'fail' },
        { cat: 'Диск', test: 'Знос SSD', value: '72% ресурсу використано', status: 'warn' },
        { cat: 'Процесор', test: 'Продуктивність під навантаженням', value: 'частота стабільна', status: 'ok' },
        { cat: 'Система', test: 'TPM', value: 'датчик недоступний', status: 'skip' }
      ],
      specs: [{ k: 'Модель', v: 'Демо' }], manual: {}
    };
  }

  render();
})();
</script>
</body>
</html>
'@

# ============================================================== допоміжне
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host ''
    Write-Host 'bibibi_test потребує прав адміністратора.' -ForegroundColor Red
    Write-Host 'Запусти bibibi_test.bat або відкрий PowerShell «від імені адміністратора» і повтори команду.' -ForegroundColor Yellow
    return
}

$Results = New-Object System.Collections.Generic.List[object]
$Specs   = New-Object System.Collections.Generic.List[object]
$Meta    = @{ hostname = $env:COMPUTERNAME; model = ''; serial = ''; os = '' }
$script:Abort = $false
$script:LastCtrlC = [datetime]::MinValue
$Started = Get-Date

function Add-R([string]$Status, [string]$Cat, [string]$Test, $Value) {
    $v = "$Value".Trim(); if (-not $v) { $v = '—' }
    $Results.Add([pscustomobject][ordered]@{ cat = $Cat; test = $Test; value = $v; status = $Status })
    $lab = @{ ok = '[ОК]    '; warn = '[УВАГА] '; fail = '[КРИТ]  '; skip = '[НЕ ПЕР]' }[$Status]
    $col = @{ ok = 'Green'; warn = 'Yellow'; fail = 'Red'; skip = 'DarkGray' }[$Status]
    Write-Host ("   {0} {1}: {2}" -f $lab, $Test, $v) -ForegroundColor $col
}
function Add-S([string]$Key, $Value) {
    $v = "$Value".Trim(); if ($v) { $Specs.Add([pscustomobject][ordered]@{ k = $Key; v = $v }) }
}
function Handle-Output($o) {
    switch ("$($o.T)") {
        'R' { Add-R $o.Status $o.Cat $o.Test $o.Value }
        'S' { Add-S $o.Key $o.Value }
        'M' { if ("$($o.Value)".Trim()) { $Meta[$o.Key] = "$($o.Value)".Trim() } }
    }
}
function Test-CtrlC {
    $hit = $false
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { $hit = $true }
        }
    } catch {}
    if ($hit) {
        $now = Get-Date
        if (($now - $script:LastCtrlC).TotalSeconds -le 2) {
            $script:Abort = $true
            Write-Host "`n   Тестування перервано — формую звіт з того, що встигли." -ForegroundColor Yellow
        } else {
            Write-Host "`n   Пропускаю тест… (ще раз Ctrl+C протягом 2 с — перервати все)" -ForegroundColor Yellow
        }
        $script:LastCtrlC = $now
    }
    return $hit
}

# Код, який виконується всередині кожного окремого тесту (окремий процес)
$Helpers = {
    $ErrorActionPreference = 'Stop'
    function R([string]$Status, [string]$Cat, [string]$Test, $Value) {
        [pscustomobject]@{ T = 'R'; Status = $Status; Cat = $Cat; Test = $Test; Value = "$Value".Trim() }
    }
    function S([string]$Key, $Value) { [pscustomobject]@{ T = 'S'; Key = $Key; Value = "$Value".Trim() } }
    function M([string]$Key, $Value) { [pscustomobject]@{ T = 'M'; Key = $Key; Value = "$Value".Trim() } }
    function GB($b) { [math]::Round([double]$b / 1GB, 1) }
    function Txt($a) { -join ($a | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) }
    function BadSerial($s) { "$s".Trim() -match '^(|0+|none|n/?a|default.*|to be filled.*|system serial.*|chassis serial.*|123456789|xxxxx+)$' }
}

function Run-Test {
    param([string]$Name, [int]$Timeout, [scriptblock]$Block, [object[]]$ArgList = @())
    Write-Host ''
    Write-Host ">> $Name" -ForegroundColor Cyan
    if ($script:Abort) { Add-R 'skip' $Name 'Тест не запускався' 'тестування перервано'; return }
    if ($ArgList.Count) { $job = Start-Job -InitializationScript $Helpers -ScriptBlock $Block -ArgumentList $ArgList }
    else { $job = Start-Job -InitializationScript $Helpers -ScriptBlock $Block }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $state = 'done'; $shown = -1
    while ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') {
        if (Test-CtrlC) { $state = 'skipped'; break }
        if ($sw.Elapsed.TotalSeconds -ge $Timeout) { $state = 'timeout'; break }
        $sec = [int]$sw.Elapsed.TotalSeconds
        if ($sec -ge 3 -and $sec -ne $shown) {
            Write-Host -NoNewline ("`r   … {0} с   (Ctrl+C — пропустити тест)   " -f $sec) -ForegroundColor DarkGray
            $shown = $sec
        }
        Start-Sleep -Milliseconds 200
    }
    if ($shown -ge 0) { Write-Host -NoNewline ("`r" + (' ' * 70) + "`r") }
    if ($state -ne 'done') { Stop-Job $job -ErrorAction SilentlyContinue }
    $jerr = $null
    $out = @(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable jerr)
    foreach ($o in $out) { Handle-Output $o }
    switch ($state) {
        'timeout' { Add-R 'skip' $Name 'Тест не завершився' "перевищено ліміт часу ($Timeout с)" }
        'skipped' { Add-R 'skip' $Name 'Тест пропущено' 'пропущено вручну (Ctrl+C)' }
    }
    if ($state -eq 'done' -and -not ($out | Where-Object { "$($_.T)" -eq 'R' })) {
        $why = 'тест не повернув результатів'
        if ($jerr) { $why = "помилка: $($jerr[0])" }
        elseif ($job.ChildJobs.Count -and $job.ChildJobs[0].JobStateInfo.Reason) { $why = "помилка: $($job.ChildJobs[0].JobStateInfo.Reason.Message)" }
        Add-R 'skip' $Name 'Помилка тесту' $why
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

function Get-UserFolders {
    # Робочий стіл і «Завантаження» того, хто сидить за екраном (а не того, хто запустив консоль)
    $r = @{ User = "$env:USERDOMAIN\$env:USERNAME"; Desktop = [Environment]::GetFolderPath('Desktop'); Downloads = '' }
    try {
        $cu = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($cu) {
            $sid = (New-Object Security.Principal.NTAccount($cu)).Translate([Security.Principal.SecurityIdentifier]).Value
            $prof = (Get-CimInstance Win32_UserProfile -Filter "SID='$sid'").LocalPath
            $key = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            $p = Get-ItemProperty -LiteralPath $key
            $expand = { param($v) if ($v) { ("$v" -ireplace '%USERPROFILE%', $prof) } else { '' } }
            $d = & $expand $p.Desktop
            $dl = & $expand $p.'{374DE290-123F-4565-9164-39C4925E467B}'
            if ($d -and $d -notmatch '%' -and (Test-Path -LiteralPath $d)) { $r.Desktop = $d; $r.User = $cu }
            if ($dl -and $dl -notmatch '%') { $r.Downloads = $dl }
            if (-not $r.Downloads -and $prof) { $r.Downloads = Join-Path $prof 'Downloads' }
        }
    } catch {}
    if (-not $r.Downloads) {
        try {
            $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
            $r.Downloads = [Environment]::ExpandEnvironmentVariables($p.'{374DE290-123F-4565-9164-39C4925E467B}')
        } catch { $r.Downloads = Join-Path $env:USERPROFILE 'Downloads' }
    }
    return $r
}

# ============================================================== тести
$T_System = {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $csp = Get-CimInstance Win32_ComputerSystemProduct
        $bios = Get-CimInstance Win32_BIOS
        $os = Get-CimInstance Win32_OperatingSystem
        $serial = "$($bios.SerialNumber)".Trim()
        if (BadSerial $serial) { $serial = "$($csp.IdentifyingNumber)".Trim() }
        if (BadSerial $serial) { $serial = '' }
        $model = "$($cs.Manufacturer) $($cs.Model)".Trim()
        $ver = "$($csp.Version)".Trim()
        if ($ver -and $ver -notmatch 'none|default|to be filled|system version' -and $model -notlike "*$ver*") { $model += " ($ver)" }
        M 'hostname' $env:COMPUTERNAME; M 'model' $model; M 'serial' $serial; M 'os' "$($os.Caption)"
        S 'Назва ПК' $env:COMPUTERNAME
        S 'Модель' $model
        S 'Серійний номер' $(if ($serial) { $serial } else { 'не вказано виробником' })
        $bd = ''; if ($bios.ReleaseDate) { $bd = ' від ' + $bios.ReleaseDate.ToString('dd.MM.yyyy') }
        S 'BIOS / UEFI' "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)$bd"
        $build = ''
        try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; $build = " $($cv.DisplayVersion), збірка $($cv.CurrentBuild).$($cv.UBR)" } catch {}
        S 'Операційна система' "$($os.Caption)$build, $($os.OSArchitecture)"
        S 'Встановлено ОС' $os.InstallDate.ToString('dd.MM.yyyy')
        if ($serial) { R 'ok' 'Система' 'Серійний номер' $serial }
        else { R 'warn' 'Система' 'Серійний номер' 'виробник не прописав серійний номер у BIOS' }
    } catch { R 'skip' 'Система' 'Відомості про систему' "не вдалося прочитати: $($_.Exception.Message)" }

    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
        if ($lic -and $lic.LicenseStatus -eq 1) { R 'ok' 'Система' 'Активація Windows' 'активовано' }
        else { R 'warn' 'Система' 'Активація Windows' 'Windows не активовано' }
    } catch { R 'skip' 'Система' 'Активація Windows' 'не вдалося перевірити' }

    try {
        if (Confirm-SecureBootUEFI) { R 'ok' 'Система' 'Secure Boot' 'увімкнено' }
        else { R 'warn' 'Система' 'Secure Boot' 'вимкнено в налаштуваннях BIOS/UEFI' }
    } catch { R 'warn' 'Система' 'Secure Boot' 'не підтримується — ПК працює в режимі Legacy BIOS' }

    try {
        $tpm = Get-Tpm
        $tv = ''
        try { $tv = (Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm).SpecVersion.Split(',')[0].Trim() } catch {}
        if ($tpm.TpmPresent -and $tpm.TpmReady) { R 'ok' 'Система' 'TPM' $(if ($tv) { "версія $tv, готовий" } else { 'готовий' }) }
        elseif ($tpm.TpmPresent) { R 'warn' 'Система' 'TPM' 'є, але не готовий до роботи' }
        else { R 'warn' 'Система' 'TPM' 'відсутній або вимкнений у BIOS' }
    } catch { R 'skip' 'Система' 'TPM' 'не вдалося перевірити' }

    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive
        S 'BitLocker (системний диск)' "$($bl.ProtectionStatus), $($bl.VolumeStatus)"
    } catch { S 'BitLocker (системний диск)' 'недоступно в цій редакції Windows' }
}

$T_Hardware = {
    try {
        $cpu = @(Get-CimInstance Win32_Processor)[0]
        $name = ($cpu.Name -replace '\s+', ' ').Trim()
        S 'Процесор' $name
        S 'Ядра / потоки' "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
        S 'Базова частота' "$($cpu.MaxClockSpeed) МГц"
        if ($cpu.ConfigManagerErrorCode -and $cpu.ConfigManagerErrorCode -ne 0) { R 'fail' 'Процесор' 'Процесор' "$name — помилка пристрою $($cpu.ConfigManagerErrorCode)" }
        else { R 'ok' 'Процесор' 'Процесор' $name }
    } catch { R 'skip' 'Процесор' 'Процесор' 'не вдалося прочитати' }

    try {
        $mods = @(Get-CimInstance Win32_PhysicalMemory)
        $total = ($mods | Measure-Object Capacity -Sum).Sum
        $slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
        $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
        $i = 0
        foreach ($m in $mods) {
            $i++
            $t = $types[[int]$m.SMBIOSMemoryType]
            $spd = $m.ConfiguredClockSpeed; if (-not $spd) { $spd = $m.Speed }
            S "Модуль пам'яті $i" ("$(GB $m.Capacity) ГБ $t $spd МГц, $($m.Manufacturer) $($m.PartNumber)" -replace '\s+', ' ')
        }
        $sl = ''; if ($slots) { $sl = ", зайнято слотів: $($mods.Count) з $slots" }
        S "Оперативна пам'ять" "$(GB $total) ГБ$sl"
        if ($total -gt 0) { R 'ok' "Пам'ять" "Оперативна пам'ять" "$(GB $total) ГБ$sl" }
        else { R 'skip' "Пам'ять" "Оперативна пам'ять" 'не вдалося визначити' }
    } catch { R 'skip' "Пам'ять" "Оперативна пам'ять" 'не вдалося прочитати' }

    try {
        $gpus = @(Get-CimInstance Win32_VideoController)
        if (-not $gpus.Count) { R 'fail' 'Відео' 'Відеоадаптер' 'не знайдено' }
        foreach ($g in $gpus) {
            $res = ''
            if ($g.CurrentHorizontalResolution) { $res = ", $($g.CurrentHorizontalResolution)×$($g.CurrentVerticalResolution) $($g.CurrentRefreshRate) Гц" }
            S 'Відеоадаптер' "$($g.Name), драйвер $($g.DriverVersion)"
            if ($g.ConfigManagerErrorCode -ne 0) { R 'fail' 'Відео' 'Відеоадаптер' "$($g.Name) — помилка пристрою (код $($g.ConfigManagerErrorCode))" }
            elseif ($g.Name -match 'Basic Display|Базов') { R 'warn' 'Відео' 'Відеоадаптер' "$($g.Name) — не встановлено драйвер відеокарти" }
            else { R 'ok' 'Відео' 'Відеоадаптер' "$($g.Name)$res" }
        }
    } catch { R 'skip' 'Відео' 'Відеоадаптер' 'не вдалося прочитати' }

    try {
        $ids = @(Get-CimInstance -Namespace root\wmi WmiMonitorID)
        $par = @(Get-CimInstance -Namespace root\wmi WmiMonitorBasicDisplayParams)
        $con = @(); try { $con = @(Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams) } catch {}
        $internal = $false
        foreach ($m in $ids) {
            $nm = (Txt $m.ManufacturerName) + ' ' + (Txt $m.UserFriendlyName)
            $p = $par | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
            $c = $con | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
            $size = ''
            if ($p -and $p.MaxHorizontalImageSize) {
                $size = ', ~' + [math]::Round([math]::Sqrt([math]::Pow($p.MaxHorizontalImageSize, 2) + [math]::Pow($p.MaxVerticalImageSize, 2)) / 2.54, 1) + '"'
            }
            $isInt = $c -and ($c.VideoOutputTechnology -eq 11 -or $c.VideoOutputTechnology -eq 6 -or $c.VideoOutputTechnology -eq -2147483648)
            if ($isInt) { $internal = $true }
            S $(if ($isInt) { 'Вбудований дисплей' } else { 'Дисплей' }) ($nm.Trim() + $size)
        }
        if ($internal) { R 'ok' 'Відео' 'Вбудований дисплей' 'визначається системою' }
        elseif ($ids.Count) { R 'ok' 'Відео' 'Дисплей' "визначено дисплеїв: $($ids.Count)" }
        else { R 'warn' 'Відео' 'Вбудований дисплей' 'система не бачить дисплей' }
    } catch { R 'skip' 'Відео' 'Дисплей' 'не вдалося прочитати' }
}

$T_Disks = {
    $disks = @()
    try { $disks = @(Get-PhysicalDisk) } catch { R 'skip' 'Диск' 'Накопичувачі' "не вдалося прочитати: $($_.Exception.Message)"; return }
    if (-not $disks.Count) { R 'fail' 'Диск' 'Накопичувачі' 'не знайдено жодного диска' }
    foreach ($d in $disks) {
        $name = "$($d.FriendlyName)".Trim()
        $hs = "$($d.HealthStatus)"
        S "Диск: $name" "$($d.MediaType), $($d.BusType), $(GB $d.Size) ГБ"
        if ($hs -in 'Healthy', '0') { R 'ok' 'Диск' "$name — стан" 'справний (Healthy)' }
        elseif ($hs -in 'Warning', '1') { R 'warn' 'Диск' "$name — стан" 'Windows попереджає про проблеми (Warning)' }
        else { R 'fail' 'Диск' "$name — стан" "несправний ($hs)" }
        try {
            $rc = $d | Get-StorageReliabilityCounter
            if ($null -ne $rc.Wear) {
                $st = 'ok'; if ($rc.Wear -ge 90) { $st = 'fail' } elseif ($rc.Wear -ge 70) { $st = 'warn' }
                R $st 'Диск' "$name — знос" "використано $($rc.Wear)% ресурсу"
            }
            if ($rc.Temperature) {
                $st = 'ok'; if ($rc.Temperature -ge 75) { $st = 'warn' }
                R $st 'Диск' "$name — температура" "$($rc.Temperature) °C"
            }
            if ($rc.PowerOnHours) { S "Диск: $name — напрацювання" "$($rc.PowerOnHours) год" }
            $errs = [int64]$rc.ReadErrorsUncorrected + [int64]$rc.WriteErrorsUncorrected
            if ($errs -gt 0) { R 'fail' 'Диск' "$name — помилки" "невиправлених помилок читання/запису: $errs" }
            elseif ($null -ne $rc.ReadErrorsUncorrected) { R 'ok' 'Диск' "$name — помилки" 'невиправлених помилок немає' }
        } catch { R 'skip' 'Диск' "$name — SMART" 'диск не віддає детальні дані SMART' }
    }
    try {
        $v = Get-Volume -DriveLetter $env:SystemDrive[0]
        $pct = [math]::Round($v.SizeRemaining / $v.Size * 100)
        $st = 'ok'; if ($pct -lt 10) { $st = 'warn' }
        R $st 'Диск' "Вільне місце на $env:SystemDrive" "$(GB $v.SizeRemaining) з $(GB $v.Size) ГБ ($pct%)"
    } catch {}
}

$T_Battery = {
    $bat = @(Get-CimInstance Win32_Battery)
    if (-not $bat.Count) { R 'fail' 'Батарея' 'Батарея' 'не знайдена (відсутня, від''єднана або несправна)'; return }
    try {
        $xmlPath = Join-Path $env:TEMP "bibibi_battery_$PID.xml"
        & powercfg.exe /batteryreport /xml /output "$xmlPath" 2>&1 | Out-Null
        [xml]$bx = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
        Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
        $i = 0
        foreach ($b in @($bx.BatteryReport.Batteries.Battery)) {
            $i++; $n = ''; if (@($bx.BatteryReport.Batteries.Battery).Count -gt 1) { $n = " $i" }
            $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity
            S "Батарея$n" ("$($b.Manufacturer) $($b.Id) $($b.Chemistry)" -replace '\s+', ' ')
            if ($design -gt 0 -and $full -gt 0) {
                $h = [math]::Round($full / $design * 100)
                $st = 'ok'; if ($h -lt 50) { $st = 'fail' } elseif ($h -lt 75) { $st = 'warn' }
                R $st 'Батарея' "Стан батареї$n" ("$h% від заводської ємності ({0:N1} з {1:N1} Вт·год)" -f ($full / 1000), ($design / 1000))
            } elseif ($design -gt 0) { R 'fail' 'Батарея' "Стан батареї$n" 'повна ємність 0 — батарея не тримає заряд' }
            else { R 'skip' 'Батарея' "Стан батареї$n" 'батарея не повідомляє ємність' }
            if ($b.CycleCount -and [int]$b.CycleCount -gt 0) {
                $st = 'ok'; if ([int]$b.CycleCount -gt 800) { $st = 'warn' }
                R $st 'Батарея' "Цикли заряду$n" $b.CycleCount
            }
        }
    } catch { R 'skip' 'Батарея' 'Стан батареї' 'не вдалося отримати звіт про батарею' }
    S 'Поточний заряд' "$($bat[0].EstimatedChargeRemaining)%"
    try {
        $bs = Get-CimInstance -Namespace root\wmi BatteryStatus | Select-Object -First 1
        if ($bs.PowerOnline) {
            $chg = ''; if ($bs.Charging) { $chg = ', батарея заряджається' }
            R 'ok' 'Батарея' 'Зарядний пристрій' "підключено$chg"
        } else { R 'warn' 'Батарея' 'Зарядний пристрій' 'не підключено — перевірте зарядку вручну' }
    } catch { R 'skip' 'Батарея' 'Зарядний пристрій' 'не вдалося перевірити' }
}

$T_Network = {
    try {
        $ad = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        $wifi = @($ad | Where-Object { "$($_.PhysicalMediaType)" -match '802\.11' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN' })
        $eth = @($ad | Where-Object { "$($_.PhysicalMediaType)" -eq '802.3' -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN' })
        if ($wifi.Count) {
            foreach ($w in $wifi) {
                S 'Wi-Fi' "$($w.InterfaceDescription), MAC $($w.MacAddress)"
                if ("$($w.Status)" -eq 'Disabled') { R 'warn' 'Мережа' 'Wi-Fi' "$($w.InterfaceDescription) — вимкнено" }
                elseif ("$($w.Status)" -eq 'Not Present') { R 'fail' 'Мережа' 'Wi-Fi' "$($w.InterfaceDescription) — не відповідає" }
                else { R 'ok' 'Мережа' 'Wi-Fi' "$($w.InterfaceDescription) — $($w.Status)" }
            }
        } else { R 'fail' 'Мережа' 'Wi-Fi' 'адаптер Wi-Fi не знайдено' }
        if ($eth.Count) {
            foreach ($e in $eth) { S 'Ethernet' "$($e.InterfaceDescription), MAC $($e.MacAddress)"; R 'ok' 'Мережа' 'Ethernet' "$($e.InterfaceDescription) — $($e.Status)" }
        } else { S 'Ethernet' 'немає вбудованого порту' }
    } catch { R 'skip' 'Мережа' 'Мережеві адаптери' 'не вдалося прочитати' }
    try {
        $bt = @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -notmatch 'Enumerator|RFCOMM|LE Generic|Identification|AVRCP|Перечислитель|перелічувач' })
        if ($bt.Count) {
            $bad = @($bt | Where-Object { "$($_.Status)" -ne 'OK' })
            if ($bad.Count) { R 'warn' 'Мережа' 'Bluetooth' "$($bad[0].FriendlyName) — $($bad[0].Status)" }
            else { R 'ok' 'Мережа' 'Bluetooth' $bt[0].FriendlyName }
        } else { R 'warn' 'Мережа' 'Bluetooth' 'адаптер не знайдено або вимкнено' }
    } catch { R 'skip' 'Мережа' 'Bluetooth' 'не вдалося перевірити' }
}

$T_Periph = {
    function Dev($class) { @(Get-PnpDevice -Class $class -PresentOnly -ErrorAction SilentlyContinue) }
    try {
        $cam = @(Dev 'Camera') + @(Dev 'Image') | Where-Object { $_ -and $_.FriendlyName -notmatch 'scan|скан|IR Camera|ІЧ|ИК' }
        $cam = @($cam)
        if ($cam.Count) {
            foreach ($c in $cam) {
                if ("$($c.Status)" -eq 'OK') { R 'ok' 'Периферія' 'Вебкамера' $c.FriendlyName }
                else { R 'fail' 'Периферія' 'Вебкамера' "$($c.FriendlyName) — $($c.Status)" }
            }
        } else { R 'warn' 'Периферія' 'Вебкамера' 'не знайдена (вимкнена клавішею/шторкою, у BIOS або несправна)' }
    } catch { R 'skip' 'Периферія' 'Вебкамера' 'не вдалося перевірити' }
    try {
        $ep = Dev 'AudioEndpoint'
        $out = @($ep | Where-Object { $_.FriendlyName -match 'Speaker|Динамік|Динамики|Headphone|Навушник|Наушник' })
        $in = @($ep | Where-Object { $_.FriendlyName -match 'Microphone|Мікрофон|Микрофон|Mic' })
        $snd = @(Get-CimInstance Win32_SoundDevice)
        foreach ($s in $snd) { S 'Аудіоконтролер' $s.Name }
        if ($out.Count) { R 'ok' 'Периферія' 'Динаміки (пристрій)' (($out | ForEach-Object FriendlyName) -join '; ') }
        elseif ($snd.Count) { R 'warn' 'Периферія' 'Динаміки (пристрій)' 'аудіоконтролер є, але вихід звуку не знайдено' }
        else { R 'fail' 'Периферія' 'Динаміки (пристрій)' 'звукову карту не знайдено' }
        if ($in.Count) { R 'ok' 'Периферія' 'Мікрофон' (($in | ForEach-Object FriendlyName) -join '; ') }
        else { R 'warn' 'Периферія' 'Мікрофон' 'мікрофон не знайдено' }
    } catch { R 'skip' 'Периферія' 'Звук' 'не вдалося перевірити' }
    try {
        $kb = @(Dev 'Keyboard'); $ms = @(Dev 'Mouse')
        if ($kb.Count) { S 'Клавіатура' (($kb | ForEach-Object FriendlyName | Select-Object -Unique) -join '; ') }
        $tp = @($ms | Where-Object { $_.FriendlyName -match 'touch ?pad|precision|synaptics|elan|alps|сенсорн' })
        if (-not $tp.Count) { $tp = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'touch ?pad|precision touchpad|сенсорна панель' }) }
        if ($tp.Count) { R 'ok' 'Периферія' 'Тачпад (пристрій)' $tp[0].FriendlyName }
        else { R 'warn' 'Периферія' 'Тачпад (пристрій)' 'тачпад не визначено як окремий пристрій — перевірте в ручному тесті' }
    } catch {}
    try {
        $fp = @(Dev 'Biometric'); if ($fp.Count) { S 'Сканер відбитків' $fp[0].FriendlyName }
        $usb = @(Get-CimInstance Win32_USBController)
        $badUsb = @($usb | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
        if ($badUsb.Count) { R 'fail' 'Периферія' 'USB-контролери' "$($badUsb[0].Name) — помилка $($badUsb[0].ConfigManagerErrorCode)" }
        elseif ($usb.Count) { R 'ok' 'Периферія' 'USB-контролери' "працюють ($($usb.Count))" }
        $cr = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Card Reader|SD Host|кардрідер' })
        if ($cr.Count) { S 'Кардрідер' $cr[0].FriendlyName }
    } catch {}
}

$T_Drivers = {
    try {
        # 22 = вимкнено вручну, 45 = пристрій зараз не підключено — це не помилки
        $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -notin 0, 22, 45 })
        if (-not $bad.Count) { R 'ok' 'Драйвери' 'Диспетчер пристроїв' 'усі пристрої працюють без помилок'; return }
        foreach ($d in ($bad | Select-Object -First 20)) {
            $n = $d.Name; if (-not $n) { $n = $d.PNPDeviceID }
            $why = "помилка пристрою, код $($d.ConfigManagerErrorCode)"
            if ($d.ConfigManagerErrorCode -eq 28) { $why = 'не встановлено драйвер' }
            if ($d.ConfigManagerErrorCode -eq 10) { $why = 'пристрій не запускається (код 10)' }
            if ($d.ConfigManagerErrorCode -eq 43) { $why = 'пристрій повідомив про збій (код 43)' }
            R 'warn' 'Драйвери' $n $why
        }
        if ($bad.Count -gt 20) { R 'warn' 'Драйвери' 'Ще пристрої з помилками' "$($bad.Count - 20) шт." }
    } catch { R 'skip' 'Драйвери' 'Диспетчер пристроїв' 'не вдалося перевірити' }
}

$T_Logs = {
    $since = (Get-Date).AddDays(-30)
    function Cnt($f) { @(Get-WinEvent -FilterHashtable $f -ErrorAction SilentlyContinue).Count }
    try {
        $n = Cnt @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since }
        $st = 'ok'; if ($n -ge 5) { $st = 'warn' }
        R $st 'Журнал Windows' 'Неочікувані вимкнення (30 днів)' $(if ($n) { "$n разів (зависання, збій живлення або вимкнення кнопкою)" } else { 'не було' })
    } catch { R 'skip' 'Журнал Windows' 'Неочікувані вимкнення' 'не вдалося прочитати журнал' }
    try {
        $n = Cnt @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
        $st = 'ok'; if ($n -ge 3) { $st = 'fail' } elseif ($n -ge 1) { $st = 'warn' }
        R $st 'Журнал Windows' 'Сині екрани (BSOD, 30 днів)' $(if ($n) { "$n разів" } else { 'не було' })
    } catch {}
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue)
        $fatal = @($ev | Where-Object { $_.Level -le 2 }).Count
        $corr = $ev.Count - $fatal
        if ($fatal) { R 'fail' 'Журнал Windows' 'Апаратні помилки WHEA (30 днів)' "критичних: $fatal, виправлених: $corr" }
        elseif ($corr -ge 10) { R 'warn' 'Журнал Windows' 'Апаратні помилки WHEA (30 днів)' "виправлених апаратних помилок: $corr" }
        else { R 'ok' 'Журнал Windows' 'Апаратні помилки WHEA (30 днів)' $(if ($corr) { "поодинокі виправлені: $corr" } else { 'не було' }) }
    } catch {}
    try {
        $n = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk', 'Ntfs', 'stornvme', 'storahci', 'iaStorAC', 'iaStorA'; Level = 1, 2, 3; StartTime = $since } -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -in 7, 11, 15, 51, 129, 153, 55, 98, 140 }).Count
        $st = 'ok'; if ($n -ge 10) { $st = 'fail' } elseif ($n -ge 1) { $st = 'warn' }
        R $st 'Журнал Windows' 'Помилки диска (30 днів)' $(if ($n) { "$n записів про збої читання/запису або файлової системи" } else { 'не було' })
    } catch {}
}

$T_DiskSpeed = {
    param($SizeMB)
    $cs = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class BibibiDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(SafeFileHandle h, IntPtr b, uint n, out uint w, IntPtr o);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(SafeFileHandle h, IntPtr b, uint n, out uint r, IntPtr o);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);
    static void Check(bool ok) { if (!ok) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
    public static double[] Run(string path, int totalMB) {
        const uint CHUNK = 4u * 1024 * 1024;
        IntPtr buf = VirtualAlloc(IntPtr.Zero, (UIntPtr)CHUNK, 0x3000, 0x04);
        if (buf == IntPtr.Zero) throw new Exception("VirtualAlloc failed");
        try {
            byte[] rnd = new byte[CHUNK]; new Random().NextBytes(rnd); Marshal.Copy(rnd, 0, buf, (int)CHUNK);
            int n = totalMB / 4; uint done;
            Stopwatch sw = Stopwatch.StartNew();
            using (SafeFileHandle h = CreateFile(path, 0x40000000, 0, IntPtr.Zero, 2, 0x20000000 | 0x80000000, IntPtr.Zero)) {
                Check(!h.IsInvalid);
                for (int i = 0; i < n; i++) Check(WriteFile(h, buf, CHUNK, out done, IntPtr.Zero));
            }
            double w = totalMB / sw.Elapsed.TotalSeconds;
            sw = Stopwatch.StartNew();
            using (SafeFileHandle h = CreateFile(path, 0x80000000, 0, IntPtr.Zero, 3, 0x20000000 | 0x08000000, IntPtr.Zero)) {
                Check(!h.IsInvalid);
                for (int i = 0; i < n; i++) { Check(ReadFile(h, buf, CHUNK, out done, IntPtr.Zero)); if (done == 0) break; }
            }
            double r = totalMB / sw.Elapsed.TotalSeconds;
            return new double[] { w, r };
        } finally { VirtualFree(buf, UIntPtr.Zero, 0x8000); }
    }
}
'@
    $path = Join-Path $env:TEMP 'bibibi_disktest.tmp'
    try {
        $letter = $env:SystemDrive[0]
        $vol = Get-Volume -DriveLetter $letter
        $need = ($SizeMB + 2048) * 1MB
        if ($vol.SizeRemaining -lt $need) { R 'skip' 'Диск' 'Швидкість диска' "замало вільного місця для тесту (потрібно $([math]::Round($need / 1GB, 1)) ГБ)"; return }
        $media = ''; $bus = ''
        try {
            $dn = (Get-Partition -DriveLetter $letter | Select-Object -First 1).DiskNumber
            $pd = Get-PhysicalDisk | Where-Object { "$($_.DeviceId)" -eq "$dn" } | Select-Object -First 1
            $media = "$($pd.MediaType)"; $bus = "$($pd.BusType)"
        } catch {}
        Add-Type -TypeDefinition $cs
        $r = [BibibiDisk]::Run($path, $SizeMB)
        $w = [math]::Round($r[0]); $rd = [math]::Round($r[1])
        if ($bus -eq 'NVMe') { $lw = 300; $lr = 500; $kind = 'NVMe SSD' }
        elseif ($media -eq 'HDD') { $lw = 40; $lr = 50; $kind = 'HDD' }
        else { $lw = 150; $lr = 200; $kind = 'SSD' }
        foreach ($x in @(@('Швидкість запису', $w, $lw), @('Швидкість читання', $rd, $lr))) {
            $st = 'ok'; if ($x[1] -lt 15) { $st = 'fail' } elseif ($x[1] -lt $x[2]) { $st = 'warn' }
            $note = ''; if ($st -ne 'ok') { $note = " (для $kind очікується від $($x[2]) МБ/с)" }
            R $st 'Диск' $x[0] "$($x[1]) МБ/с$note"
        }
    } catch { R 'skip' 'Диск' 'Швидкість диска' "не вдалося виміряти: $($_.Exception.Message)" }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Run-Stress {
    $title = "Навантаження процесора ($([math]::Round($CpuSeconds / 60, 1)) хв)"
    Write-Host ''
    Write-Host ">> $title" -ForegroundColor Cyan
    if ($script:Abort) { Add-R 'skip' 'Навантаження' 'Тест не запускався' 'тестування перервано'; return }
    Write-Host '   Вентилятор загуде — це нормально. Краще підключити зарядку. Ctrl+C — пропустити.' -ForegroundColor DarkGray
    $n = [Environment]::ProcessorCount
    $onAC = $true
    try { $bs = Get-CimInstance -Namespace root\wmi BatteryStatus | Select-Object -First 1; if ($bs) { $onAC = [bool]$bs.PowerOnline } } catch {}
    $samples = New-Object System.Collections.Generic.List[object]
    $pool = $null; $workers = @(); $state = 'done'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $pool = [runspacefactory]::CreateRunspacePool(1, $n); $pool.Open()
        $work = { param($sec) $end = [DateTime]::UtcNow.AddSeconds($sec); $x = 0.0
            while ([DateTime]::UtcNow -lt $end) { for ($i = 1; $i -lt 50000; $i++) { $x += [math]::Sqrt($i) * [math]::Sin($i) } } }
        for ($i = 0; $i -lt $n; $i++) {
            $ps = [powershell]::Create(); $ps.RunspacePool = $pool
            [void]$ps.AddScript($work).AddArgument($CpuSeconds + 10)
            $workers += [pscustomobject]@{ P = $ps; H = $ps.BeginInvoke() }
        }
        $sw.Restart(); $next = 0
        while ($sw.Elapsed.TotalSeconds -lt $CpuSeconds) {
            if (Test-CtrlC) { $state = 'skipped'; break }
            if ($sw.Elapsed.TotalSeconds -ge $next) {
                $next += 3
                try {
                    $pc = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
                    $temp = $null
                    try {
                        $tz = @(Get-CimInstance -Namespace root\wmi MSAcpi_ThermalZoneTemperature) | Where-Object { $_.CurrentTemperature -gt 2732 }
                        if ($tz.Count) { $temp = [math]::Round((($tz | Measure-Object CurrentTemperature -Maximum).Maximum) / 10 - 273.15) }
                    } catch {}
                    $s = [pscustomobject]@{ T = $sw.Elapsed.TotalSeconds; Load = [int]$pc.PercentProcessorTime; Perf = [int]$pc.PercentProcessorPerformance; MHz = [int]$pc.ProcessorFrequency; Temp = $temp }
                    $samples.Add($s)
                    $tt = ''; if ($null -ne $temp) { $tt = " · ~$temp °C" }
                    $eff = ''; if ($s.MHz -and $s.Perf) { $eff = " · ~$([math]::Round($s.MHz * $s.Perf / 100)) МГц" }
                    Write-Host -NoNewline ("`r   залишилось {0,3} с · навантаження {1,3}%{2}{3}        " -f [int]($CpuSeconds - $s.T), $s.Load, $eff, $tt) -ForegroundColor DarkGray
                } catch {}
            }
            Start-Sleep -Milliseconds 250
        }
        Write-Host ''
    } catch {
        Write-Host ''
        Add-R 'skip' 'Навантаження' 'Стрес-тест' "помилка: $($_.Exception.Message)"; $state = 'error'
    } finally {
        foreach ($w in $workers) { try { $w.P.Stop() } catch {}; try { $w.P.Dispose() } catch {} }
        if ($pool) { try { $pool.Close(); $pool.Dispose() } catch {} }
    }
    $ran = [int]$sw.Elapsed.TotalSeconds
    if ($state -eq 'skipped') { Add-R 'skip' 'Навантаження' 'Тест пропущено' "пропущено вручну (Ctrl+C) через $ran с" }
    $v = @($samples | Where-Object { $_.T -ge 10 })
    if ($v.Count -lt 4) { if ($state -eq 'done') { Add-R 'skip' 'Навантаження' 'Стрес-тест' 'не вдалося зняти показники процесора' }; return }
    $avgLoad = [math]::Round(($v | Measure-Object Load -Average).Average)
    $third = [math]::Max(2, [math]::Floor($v.Count / 3))
    $p1 = ($v | Select-Object -First $third | Measure-Object Perf -Average).Average
    $p3 = ($v | Select-Object -Last $third | Measure-Object Perf -Average).Average
    $mhz = ($v | Select-Object -First 1).MHz
    $acNote = ''; if (-not $onAC) { $acNote = ' Тест ішов від батареї — результат може бути занижений.' }
    if ($avgLoad -ge 80) { Add-R 'ok' 'Навантаження' 'Завантаження процесора' "середнє $avgLoad% на $n потоках протягом $ran с" }
    else { Add-R 'warn' 'Навантаження' 'Завантаження процесора' "лише $avgLoad% — процесор не вийшов на повне навантаження (енергозбереження?).$acNote" }
    if ($p1 -gt 0 -and $mhz -gt 0) {
        $f1 = [math]::Round($mhz * $p1 / 100); $f3 = [math]::Round($mhz * $p3 / 100)
        $drop = [math]::Round((1 - $p3 / $p1) * 100)
        if ($drop -ge 35 -or $p3 -lt 50) {
            Add-R 'warn' 'Навантаження' 'Троттлінг (скидання частоти)' "частота впала з ~$f1 до ~$f3 МГц (−$drop%) — перегрів, пил у системі охолодження або висохла термопаста.$acNote"
        } else {
            Add-R 'ok' 'Навантаження' 'Троттлінг (скидання частоти)' "частота стабільна: ~$f1 → ~$f3 МГц"
        }
    } else { Add-R 'skip' 'Навантаження' 'Троттлінг (скидання частоти)' 'Windows не віддає дані про частоту' }
    $tv = @($v | Where-Object { $null -ne $_.Temp })
    if ($tv.Count) {
        $mt = ($tv | Measure-Object Temp -Maximum).Maximum
        $st = 'ok'; if ($mt -ge 100) { $st = 'fail' } elseif ($mt -ge 92) { $st = 'warn' }
        Add-R $st 'Навантаження' 'Температура під навантаженням' "максимум ~$mt °C (датчик ACPI, точність приблизна)"
    } else { Add-R 'skip' 'Навантаження' 'Температура під навантаженням' 'Windows не віддає температуру процесора без сторонніх програм' }
    if ($state -eq 'done') { Add-R 'ok' 'Навантаження' 'Стабільність' "система не зависла під повним навантаженням $ran с" }
}

# ============================================================== звіт
function Safe-Name([string]$s) { ($s -replace '[\\/:*?"<>|\[\]]', '_' -replace '\s+', ' ').Trim(' .') }

function Build-Html([string]$FileName) {
    $data = [ordered]@{
        version = $BibibiVersion
        final   = $false
        meta    = [ordered]@{
            hostname = $Meta.hostname; model = $Meta.model; serial = $Meta.serial; os = $Meta.os
            platform = 'windows'; date = (Get-Date -Format 'yyyy-MM-dd'); datetime = (Get-Date -Format 'dd.MM.yyyy HH:mm')
            duration = "$([math]::Round(((Get-Date) - $Started).TotalMinutes))"; filename = $FileName; user = $UF.User
        }
        results = @($Results)
        specs   = @($Specs)
        manual  = @{}
    }
    $json = ($data | ConvertTo-Json -Depth 6 -Compress).Replace('</', '<\/')
    return $Template.Replace('__BIBIBI_DATA__', $json)
}

function Save-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

# ============================================================== запуск
$prevCtrlC = $false
try { $prevCtrlC = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch {}
try { $Host.UI.RawUI.WindowTitle = 'bibibi_test' } catch {}
try {
    Clear-Host
    Write-Host '=====================================================' -ForegroundColor Magenta
    Write-Host "   bibibi_test $BibibiVersion — тестування ноутбука" -ForegroundColor Magenta
    Write-Host '=====================================================' -ForegroundColor Magenta
    Write-Host '   Тривалість: близько 15 хвилин. Ctrl+C — пропустити поточний тест,'
    Write-Host '   двічі Ctrl+C — перервати все (звіт все одно буде).'
    $UF = Get-UserFolders
    Write-Host "   Звіт буде збережено на робочий стіл: $($UF.Desktop)" -ForegroundColor DarkGray

    Run-Test 'Система' 120 $T_System
    Run-Test "Процесор, пам'ять, відео" 120 $T_Hardware
    Run-Test 'Накопичувачі' 180 $T_Disks
    Run-Test 'Батарея' 120 $T_Battery
    Run-Test 'Мережа' 90 $T_Network
    Run-Test 'Периферія' 120 $T_Periph
    Run-Test 'Драйвери' 90 $T_Drivers
    Run-Test 'Журнал Windows' 180 $T_Logs
    Run-Stress
    Run-Test "Швидкість диска ($([math]::Round($DiskTestMB / 1024, 1)) ГБ)" 900 $T_DiskSpeed @($DiskTestMB)

    # ---------- проміжний звіт
    Write-Host ''
    Write-Host '>> Звіт' -ForegroundColor Cyan
    $sn = Safe-Name $Meta.serial; if (-not $sn) { $sn = 'невідомо' }
    $base = "$(Safe-Name $Meta.hostname) - SN $sn - $(Get-Date -Format 'yyyy-MM-dd')"
    $desk = $UF.Desktop
    if (Test-Path -LiteralPath (Join-Path $desk "$base.html")) { $base += " $(Get-Date -Format 'HH-mm')" }
    $fileName = "$base.html"
    $reportPath = Join-Path $desk $fileName
    $html = Build-Html $fileName
    try { Save-Text $reportPath $html }
    catch {
        $desk = Join-Path $env:PUBLIC 'Desktop'
        $reportPath = Join-Path $desk $fileName
        Save-Text $reportPath $html
        Write-Host "   Не вдалося записати на робочий стіл користувача — збережено на загальний робочий стіл." -ForegroundColor Yellow
    }
    $fails = @($Results | Where-Object status -eq 'fail').Count
    $warns = @($Results | Where-Object status -eq 'warn').Count
    $skips = @($Results | Where-Object status -eq 'skip').Count
    Write-Host "   Автоматичні тести: критично $fails · зауважень $warns · не перевірено $skips"
    Write-Host "   Проміжний звіт: $reportPath" -ForegroundColor Green

    if ($NoBrowser) { return }

    # ---------- ручні тести в браузері
    $mark = Get-Date
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $reportPath + '"')
    Write-Host ''
    Write-Host '>> Ручні тести' -ForegroundColor Cyan
    Write-Host '   У браузері відкрився звіт. Пройдіть ручні тести (екран, звук, клавіатура, тачпад)'
    Write-Host '   і натисніть «Зберегти звіт» — файл автоматично перенесеться на робочий стіл.'
    Write-Host '   Чекаю на фінальний звіт… (Enter — завершити без нього)' -ForegroundColor DarkGray
    $dirs = @($UF.Downloads, $desk) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $final = $null
    while ($true) {
        $cand = Get-ChildItem -LiteralPath $dirs -Filter '*.html' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $mark -and $_.FullName -ne $reportPath -and $_.Name.StartsWith($base) } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) {
            Start-Sleep -Milliseconds 800
            $txt = ''
            try { $txt = [IO.File]::ReadAllText($cand.FullName) } catch {}
            if ($txt.Contains('"final":true')) {
                Move-Item -LiteralPath $cand.FullName -Destination $reportPath -Force
                $final = $txt; break
            }
        }
        $stop = $false
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq [ConsoleKey]::Enter -or ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control))) { $stop = $true }
            }
        } catch {}
        if ($stop) { break }
        Start-Sleep -Milliseconds 700
    }

    Write-Host ''
    if ($final) {
        $verdict = ''; if ($final -match '"verdict":"([^"]*)"') { $verdict = $Matches[1] }
        $c = @{}; foreach ($k in 'fail', 'warn', 'ok', 'skip') { if ($final -match ('"summary":\{[^}]*"' + $k + '":(\d+)')) { $c[$k] = $Matches[1] } else { $c[$k] = '?' } }
        $col = 'Green'; if ($verdict -match 'КРИТИЧ') { $col = 'Red' } elseif ($verdict -match 'ЗАУВАЖ') { $col = 'Yellow' }
        Write-Host "   ВИСНОВОК: $verdict" -ForegroundColor $col
        Write-Host "   Критично: $($c.fail) · зауважень: $($c.warn) · норма: $($c.ok) · не перевірено: $($c.skip)"
        Write-Host "   Фінальний звіт: $reportPath" -ForegroundColor Green
    } else {
        Write-Host "   Фінальний звіт не збережено. На робочому столі лишився проміжний: $reportPath" -ForegroundColor Yellow
    }
}
finally {
    Remove-Item -LiteralPath (Join-Path $env:TEMP 'bibibi_disktest.tmp') -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'bibibi_battery_*.xml' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    try { [Console]::TreatControlCAsInput = $prevCtrlC } catch {}
    Write-Host ''
    Write-Host '   bibibi_test завершено.' -ForegroundColor Magenta
}
