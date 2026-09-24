/*
 * RDBridge — yerel uygulama (iOS JavaScriptCore, Android WebView) için durum tutan köprü.
 *
 * Yerel ekran yalnız eylem gönderir ve JSON görünüm alır; tüm kurallar (öneri, dallanma, dışlayıcı seçenek,
 * varsayılan cevap, skor, dışa aktarma) burada ve rd-engine.js'dedir. Böylece iki platform aynı davranır.
 *
 *   RDBridge.init(dataJsonText)                  → {version, counts}
 *   RDBridge.start({company, workplace, date})   → view
 *   RDBridge.act({type, ...})                    → view
 *   RDBridge.view()  RDBridge.result()  RDBridge.sectors(q)  RDBridge.search(kind, q)
 *   RDBridge.file('xlsx'|'docx')                 → {name, base64}
 *   RDBridge.blocks()                            → PDF için metin blokları
 *
 * Tüm dönüşler düz JSON'dur (Map/Set yok).
 */
(function (root) {
  'use strict';
  const ENG = root.RDEngine;
  const REPORT = root.RDReport;
  const X = root.RDXlsx;
  let D = null, E = null, S = null;

  const HIER_KEY = {1: 'elimination', 2: 'substitution', 3: 'engineering', 4: 'administrative', 5: 'ppe'};
  const HIER_LABEL = {1: 'Ortadan kaldırma', 2: 'İkame', 3: 'Mühendislik', 4: 'İdari', 5: 'KKD'};
  const GHS = {GHS01: 'Patlayıcı', GHS02: 'Alevlenir', GHS03: 'Oksitleyici', GHS04: 'Basınçlı gaz', GHS05: 'Aşındırıcı',
    GHS06: 'Akut toksik', GHS07: 'Zararlı', GHS08: 'Sağlık tehlikesi', GHS09: 'Çevre'};
  const PRESETS = {
    standard: ['no', 'section', 'hazard', 'risk', 'consequence', 'affected', 'existing', 'fk', 'm5', 'controls', 'owner', 'deadline', 'rfk', 'rm5', 'legal'],
    compact: ['no', 'hazard', 'risk', 'fk', 'm5', 'controls', 'owner', 'deadline', 'rfk', 'rm5'],
  };
  const POPULAR = ['S182', 'S139', 'S019', 'S164', 'S127', 'S172', 'S141', 'S054', 'S145', 'S207', 'S223', 'S248'];
  const TR = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  const norm = s => String(s || '').toLocaleLowerCase('tr').replace(/i̇/g, 'i').replace(/[çğıöşüâîû]/g, c => TR[c] || c);
  const b64 = bytes => {
    const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out = '';
    for (let i = 0; i < bytes.length; i += 3) {
      const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
      out += A[a >> 2] + A[((a & 3) << 4) | ((b || 0) >> 4)] + (i + 1 < bytes.length ? A[((b & 15) << 2) | ((c || 0) >> 6)] : '=') + (i + 2 < bytes.length ? A[c & 63] : '=');
    }
    return out;
  };
  const toggle = (list, id) => { const i = list.indexOf(id); if (i >= 0) list.splice(i, 1); else list.push(id); };

  function fresh(opts) {
    opts = opts || {};
    return {firm: {name: opts.name || '', address: opts.address || '', employees: '10-49', date: opts.date || ''},
      sectors: [], hc: null, fu: {}, areas: [], equipment: [], materials: [], tasks: [], seen: {}, cond: [], mgmtOff: [],
      method: 'both', preset: 'standard', cols: PRESETS.standard.slice(), removed: [], edits: {}};
  }

  function steps() {
    const s = ['firm', 'sector'];
    E.activeFollowups(S).forEach(f => s.push('fu:' + f.id));
    return s.concat(['areas', 'equipment', 'materials', 'tasks', 'cond', 'mgmt', 'method', 'cols', 'summary']);
  }

  function pickItem(kind, x, why, selected) {
    let sub = x.g || '';
    if (kind === 'areas') sub = x.p ? ((E.AREA.get(x.p) || {}).n || '') : 'Genel alan';
    if (kind === 'materials' && x.st) sub += ' · ' + x.st;
    const tags = (why || []).slice(0, 2);
    const extra = [];
    if (kind === 'materials') (x.ghs || []).forEach(g => extra.push(GHS[g] || g));
    if (kind === 'equipment' && x.pi) extra.push('Periyodik kontrol');
    return {id: x.id, title: x.n, subtitle: sub, reasons: tags, badges: extra, selected: !!selected,
      detail: kind === 'materials' && selected ? (x.hz || '') : ''};
  }

  function picks(kind) {
    const sug = E.suggestions(S, kind);
    const chosen = new Set(S[kind]);
    const suggested = [...sug.keys()].map(id => pickItem(kind, E.POOL[kind].get(id), sug.get(id), chosen.has(id)));
    const added = [...chosen].filter(id => !sug.has(id) && E.POOL[kind].has(id)).map(id => pickItem(kind, E.POOL[kind].get(id), [], true));
    const generic = kind === 'areas' ? [...E.AREA.values()].filter(a => !a.p && !sug.has(a.id) && !chosen.has(a.id)).map(a => pickItem(kind, a, [], false)) : [];
    return {suggested, added, generic, allSelected: suggested.length > 0 && suggested.every(x => x.selected), count: chosen.size};
  }

  function counts(rows) {
    const c = {fk: {}, rfk: {}, m5: {}, rm5: {}};
    rows.forEach(({r}) => {
      const s = E.scoreOf(S, r);
      const inc = (m, k) => { m[k] = (m[k] || 0) + 1; };
      inc(c.fk, ENG.fkLevel(ENG.fkR(s.fk))[2]); inc(c.rfk, ENG.fkLevel(ENG.fkR(s.rfk))[2]);
      inc(c.m5, ENG.m5Level(ENG.m5R(s.m5))[2]); inc(c.rm5, ENG.m5Level(ENG.m5R(s.rm5))[2]);
    });
    return c;
  }

  function view() {
    const rows = E.rows(S);
    const hc = E.hazardClass(S);
    const fus = E.activeFollowups(S).map(f => ({
      id: f.id, question: f.q, help: f.h || (f.k === 'multi' ? 'Birden fazla seçebilirsiniz.' : 'Birini seçin.'), multi: f.k === 'multi',
      context: (f.s.filter(id => S.sectors.includes(id)).map(id => E.SEC.get(id).n)[0]) || 'Takip sorusu',
      options: f.o.map(o => {
        const sg = o.sg || {};
        const n = (sg.equipment || []).length + (sg.materials || []).length + (sg.tasks || []).length;
        const badges = [];
        if (n) badges.push(n + ' öneri ekler');
        if ((o.r || []).length) badges.push(o.r.length + ' risk');
        if (o.ex) badges.push('Diğerlerini temizler');
        return {id: o.id, title: o.l, badges, selected: E.answered(S, f.id).includes(o.id), exclusive: !!o.ex};
      }),
    }));
    return {
      steps: steps(), firm: S.firm, hazardClass: hc, hazardClassLabel: hc ? ENG.HC[hc] : '', hazardClassManual: !!S.hc,
      sectors: S.sectors.map(id => { const s = E.SEC.get(id); return {id, title: s.n, group: s.g, nace: s.nace, hazardClass: s.hc}; }),
      followups: fus,
      picks: {areas: picks('areas'), equipment: picks('equipment'), materials: picks('materials'), tasks: picks('tasks')},
      conditions: Object.entries(D.cond).map(([id, label]) => ({id, title: label, selected: S.cond.includes(id)})),
      management: E.managementItems(S).map(r => ({id: r.id, title: r.hz, subtitle: r.sc, selected: !S.mgmtOff.includes(r.id)})),
      method: S.method, preset: S.preset,
      columns: REPORT.COLUMNS.filter(c => !c.method || (c.method === 'fk' ? S.method !== 'm5' : S.method !== 'fk'))
        .map(c => ({id: c.id, title: c.label, required: !!c.required, residual: !!c.residual, selected: !!c.required || S.cols.includes(c.id)})),
      rowCount: rows.length, counts: counts(rows),
    };
  }

  function levelView(lv, n) { return {score: n, label: lv[1], level: lv[2]}; }

  function result() {
    const removed = new Set(S.removed);
    const all = E.rows(S);
    const active = all.filter(x => !removed.has(x.r.id));
    const numbers = new Map(active.map((x, i) => [x.r.id, i + 1]));
    return {
      counts: counts(active), total: active.length, removedCount: removed.size, method: S.method,
      rows: all.map(({r, why}) => {
        const s = E.scoreOf(S, r);
        return {
          id: r.id, number: numbers.get(r.id) || 0, section: D.fam[r.fam] || r.fam, hazard: r.hz, risk: r.sc, consequence: r.cs,
          affected: r.af, check: r.chk, reasons: why.slice(0, 4), owner: D.roles[r.own] || '', legal: r.lg.map(x => D.legal[x] || x),
          controls: r.ctl.map(c => ({hierarchy: HIER_KEY[c[0]], label: HIER_LABEL[c[0]], text: c[1], owner: D.roles[c[2]] || ''})),
          fk: Object.assign({}, s.fk, levelView(ENG.fkLevel(ENG.fkR(s.fk)), ENG.fkR(s.fk))),
          rfk: Object.assign({}, s.rfk, levelView(ENG.fkLevel(ENG.fkR(s.rfk)), ENG.fkR(s.rfk))),
          m5: Object.assign({}, s.m5, levelView(ENG.m5Level(ENG.m5R(s.m5)), ENG.m5R(s.m5))),
          rm5: Object.assign({}, s.rm5, levelView(ENG.m5Level(ENG.m5R(s.rm5)), ENG.m5R(s.rm5))),
          m5Manual: !!((S.edits[r.id] || {}).m5), rm5Manual: !!((S.edits[r.id] || {}).rm5),
          edited: s.edited, removed: removed.has(r.id), isNew: !!r.nw, severe: !!r.sev,
        };
      }),
    };
  }

  function act(a) {
    switch (a.type) {
      case 'firm': S.firm[a.field] = String(a.value == null ? '' : a.value); break;
      case 'sector':
        toggle(S.sectors, a.id); S.hc = null;
        break;
      case 'hc': S.hc = a.id || null; break;
      case 'fu': {
        const f = E.FU.get(a.fid);
        if (!f) break;
        const cur = E.answered(S, f.id).slice();
        const o = f.o.find(x => x.id === a.id);
        if (!o) break;
        let next;
        if (f.k === 'single' || o.ex) next = cur.includes(a.id) ? [] : [a.id];
        else { next = cur.filter(x => !(f.o.find(y => y.id === x) || {}).ex); toggle(next, a.id); }
        S.fu[f.id] = next;
        break;
      }
      case 'pick': if (E.POOL[a.kind]) toggle(S[a.kind], a.id); break;
      case 'all': {
        const sug = [...E.suggestions(S, a.kind).keys()];
        const on = sug.every(id => S[a.kind].includes(id));
        S[a.kind] = on ? S[a.kind].filter(id => !sug.includes(id)) : [...new Set(S[a.kind].concat(sug))];
        break;
      }
      case 'enter':
        // Alanlar ilk açıldığında önerilenler seçili gelir; diğer adımlar kullanıcı seçer.
        if (a.step === 'areas' && !S.seen.areas) { S.areas = [...new Set(S.areas.concat([...E.suggestions(S, 'areas').keys()]))]; S.seen.areas = true; }
        break;
      case 'cond': toggle(S.cond, a.id); break;
      case 'mg': toggle(S.mgmtOff, a.id); break;
      case 'mgAll': S.mgmtOff = S.mgmtOff.length ? [] : E.managementItems(S).map(r => r.id); break;
      case 'method': S.method = a.id; break;
      case 'preset': if (PRESETS[a.id]) { S.preset = a.id; S.cols = PRESETS[a.id].slice(); } else if (a.id === 'full') { S.preset = 'full'; S.cols = REPORT.COLUMNS.map(c => c.id); } break;
      case 'col': { const c = REPORT.COLUMNS.find(x => x.id === a.id); if (c && !c.required) { toggle(S.cols, a.id); S.preset = 'custom'; } break; }
      case 'edit': {
        const r = E.RISK.get(a.id);
        if (!r) break;
        const ed = S.edits[a.id] = S.edits[a.id] || {};
        const v = Number(a.value);
        if (a.key === 'fk' || a.key === 'rfk') ed[(a.key === 'rfk' ? 'r' : '') + a.field] = v;
        else ed[a.key] = Object.assign({}, E.scoreOf(S, r)[a.key], {[a.field]: v});
        break;
      }
      case 'reset': delete S.edits[a.id]; break;
      case 'remove': if (!S.removed.includes(a.id)) S.removed.push(a.id); break;
      case 'restore': S.removed = S.removed.filter(x => x !== a.id); break;
      default: break;
    }
    E.applyDefaults(S);
    return view();
  }

  function sectors(q) {
    q = norm(q);
    if (q.length < 2) return POPULAR.filter(id => E.SEC.has(id)).map(id => sectorItem(E.SEC.get(id)));
    const hits = [];
    D.sectors.forEach(s => {
      const hay = norm([s.n, s.g, s.al.join(' '), s.nace.join(' ')].join(' '));
      const score = norm(s.n).startsWith(q) ? 3 : norm(s.n).includes(q) ? 2 : hay.includes(q) ? 1 : 0;
      if (score) hits.push([score, s]);
    });
    hits.sort((a, b) => b[0] - a[0] || a[1].n.localeCompare(b[1].n, 'tr'));
    return hits.slice(0, 30).map(([, s]) => sectorItem(s));
  }
  function sectorItem(s) {
    return {id: s.id, title: s.n, subtitle: s.g + (s.nace.length ? ' · NACE ' + s.nace.join(', ') : ''), hazardClass: s.hc,
      hazardClassLabel: s.hc ? ENG.HC[s.hc] : '', selected: S.sectors.includes(s.id)};
  }
  function search(kind, q) {
    q = norm(q);
    if (q.length < 2 || !E.POOL[kind]) return [];
    const sug = E.suggestions(S, kind);
    const chosen = new Set(S[kind]);
    return [...E.POOL[kind].values()].filter(x => !sug.has(x.id) && !chosen.has(x.id) && norm(x.n + ' ' + (x.al || []).join(' ') + ' ' + (x.g || '')).includes(q))
      .slice(0, 30).map(x => pickItem(kind, x, [], false));
  }

  function fileName(ext) {
    const safe = (S.firm.name || 'Risk_Analizi').replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_|_$/g, '').slice(0, 60) || 'Risk_Analizi';
    return safe + '_Risk_Degerlendirmesi_' + (S.firm.date || '').replace(/\./g, '-') + '.' + ext;
  }
  function file(format) {
    const input = E.reportInput(S);
    const bytes = format === 'docx' ? REPORT.docx(input) : REPORT.build(input);
    return {name: fileName(format === 'docx' ? 'docx' : 'xlsx'), base64: b64(bytes), rows: input.rows.length};
  }
  function blocks() { return REPORT.blocks(E.reportInput(S)); }

  root.RDBridge = {
    init(text) {
      D = typeof text === 'string' ? JSON.parse(text) : text;
      E = ENG.create(D);
      S = fresh();
      return {version: D.v, risks: D.risks.length, sectors: D.sectors.length, equipment: D.equipment.length, materials: D.materials.length};
    },
    start(opts) { S = fresh(opts); return view(); },
    act, view, result, sectors, search, file, blocks, fileName,
    state() { return JSON.parse(JSON.stringify(S)); },
    restore(state) { S = Object.assign(fresh(), state || {}); return view(); },
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.RDBridge;
})(typeof globalThis !== 'undefined' ? globalThis : this);
