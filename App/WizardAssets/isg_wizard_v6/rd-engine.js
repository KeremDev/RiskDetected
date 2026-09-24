/*
 * RDEngine — risk analizi sihirbazının seçim ve skor motoru (V6 katalog).
 *
 * Saf fonksiyonlar: DOM, ağ ve saat kullanmaz; aynı kod tarayıcıda, Node'da ve uygulama içi
 * JavaScriptCore / WebView'da çalışır. Girdi `state` (kullanıcı cevapları), çıktı risk satırları ve rapor girdisi.
 *
 * state = {
 *   firm: {name, address, employees: '1-9'|'10-49'|'50-249'|'250+', date: 'gg.aa.yyyy'},
 *   sectors: [S…], hc: null|'low'|'medium'|'high', fu: {FU-…: [seçenek]},
 *   areas: [...], equipment: [...], materials: [...], tasks: [...], cond: [...], mgmtOff: [R-53-…],
 *   method: 'both'|'fk'|'m5', cols: [sütun], removed: [R-…], edits: {R-…: {p,f,s,rp,rf,rs, m5:{l,s}, rm5:{l,s}}}
 * }
 */
(function (root) {
  'use strict';

  const SFK = {1: 1, 2: 3, 3: 7, 4: 15, 5: 40, 6: 100};
  const FK2M5 = {1: 1, 3: 2, 7: 3, 15: 4, 40: 5, 100: 5};
  const L5 = pf => pf <= 5 ? 1 : pf <= 12 ? 2 : pf <= 18 ? 3 : pf <= 30 ? 4 : 5;
  const FK_LEVELS = [[400, 'Tolerans dışı', 'critical'], [200, 'Yüksek risk', 'high'], [70, 'Önemli risk', 'medium'], [20, 'Olası risk', 'low'], [-1, 'Önemsiz', 'insignificant']];
  const M5_LEVELS = [[19, 'Tolerans dışı', 'critical'], [9, 'Yüksek risk', 'high'], [4, 'Orta risk', 'medium'], [2, 'Düşük risk', 'low'], [-1, 'Önemsiz', 'insignificant']];
  const HC = {low: 'Az tehlikeli', medium: 'Tehlikeli', high: 'Çok tehlikeli'};
  const HIER = {1: 'Ortadan kaldırma', 2: 'İkame', 3: 'Mühendislik', 4: 'İdari', 5: 'KKD'};
  const EMP = {'1-9': '1–9', '10-49': '10–49', '50-249': '50–249', '250+': '250+'};
  const RENEW = {high: 2, medium: 4, low: 6};
  const DEADLINE = {critical: 'Hemen (iş durdurulur)', high: 'Kısa vadede', medium: 'Plan dahilinde', low: 'İzleme', insignificant: '—'};
  const fkR = v => Math.round(v.p * v.f * v.s * 100) / 100;
  const m5R = v => v.l * v.s;
  const fkLevel = r => FK_LEVELS.find(([min]) => r > min);
  const m5Level = r => M5_LEVELS.find(([min]) => r > min);

  function create(D) {
    const RISK = new Map(D.risks.map(a => [a[0], {id: a[0], fam: a[1], hz: a[2], sc: a[3], cs: a[4], af: a[5], ctl: a[6], own: a[7], lg: a[8],
      s: a[9], sev: a[10], req: a[11], chk: a[12], nw: a[13]}]));
    const by = arr => new Map(arr.map(x => [x.id, x]));
    const SEC = by(D.sectors), AREA = by(D.areas), EQ = by(D.equipment), TASK = by(D.tasks), MAT = by(D.materials), FU = by(D.followups);
    const POOL = {areas: AREA, equipment: EQ, tasks: TASK, materials: MAT};

    function hazardClass(st) {
      if (st.hc) return st.hc;
      const order = ['low', 'medium', 'high'];
      let best = null;
      st.sectors.forEach(id => { const h = SEC.get(id) && SEC.get(id).hc; if (h && (!best || order.indexOf(h) > order.indexOf(best))) best = h; });
      return best;
    }
    const answered = (st, fid) => (st.fu && st.fu[fid]) || [];

    /** Seçili faaliyetlerin, önceki cevaplara göre görünür takip soruları (sırayla). */
    function activeFollowups(st) {
      const out = [];
      const seen = new Set();
      st.sectors.forEach(sid => {
        const s = SEC.get(sid);
        if (!s) return;
        s.fu.forEach(fid => {
          const f = FU.get(fid);
          if (!f || seen.has(fid)) return;
          if (f.si && !Object.entries(f.si).every(([k, vals]) => answered(st, k).some(v => vals.includes(v)))) return;
          seen.add(fid);
          out.push(f);
        });
      });
      return out;
    }
    /** Faaliyete göre varsayılan cevaplar (ör. LPG istasyonunda "LPG otogaz" seçili gelir). */
    function applyDefaults(st) {
      activeFollowups(st).forEach(f => {
        if (st.fu[f.id]) return;
        const d = f.o.filter(o => o.d.some(sid => st.sectors.includes(sid))).map(o => o.id);
        if (d.length) st.fu[f.id] = d;
      });
      return st;
    }
    function chosenOptions(st) {
      const out = [];
      activeFollowups(st).forEach(f => answered(st, f.id).forEach(oid => { const o = f.o.find(x => x.id === oid); if (o) out.push(o); }));
      return out;
    }
    /** Seçimlerden türeyen özellikler; katalogdaki özellik çıkarımları kapanana kadar uygulanır. */
    function features(st) {
      const F = new Set();
      st.sectors.forEach(id => (SEC.get(id) ? SEC.get(id).f : []).forEach(x => F.add(x)));
      const hc = hazardClass(st);
      if (hc) F.add('hazard_class_' + hc);
      const emp = st.firm && st.firm.employees;
      if (emp && emp !== '1-9') F.add('employee_count_10plus');
      if (emp === '50-249' || emp === '250+') F.add('employee_count_50plus');
      chosenOptions(st).forEach(o => o.f.forEach(x => F.add(x)));
      (st.areas || []).forEach(id => F.add(id));
      [['equipment', EQ], ['tasks', TASK], ['materials', MAT]].forEach(([k, pool]) => (st[k] || []).forEach(id => (pool.get(id) ? pool.get(id).f : []).forEach(x => F.add(x))));
      (st.cond || []).forEach(x => F.add(x));
      let grew = true;
      while (grew) {
        grew = false;
        [...F].forEach(x => (D.fi[x] || []).forEach(y => { if (!F.has(y)) { F.add(y); grew = true; } }));
      }
      return F;
    }
    /** Bir adımda önerilecek seçenekler ve öneri gerekçeleri. */
    function suggestions(st, kind) {
      const m = new Map();
      const add = (id, why) => { if (!POOL[kind].has(id)) return; if (!m.has(id)) m.set(id, []); if (!m.get(id).includes(why)) m.get(id).push(why); };
      st.sectors.forEach(sid => { const s = SEC.get(sid); if (s) (s.sg[kind] || []).forEach(id => add(id, s.n)); });
      chosenOptions(st).forEach(o => ((o.sg || {})[kind] || []).forEach(id => add(id, o.l)));
      if (kind !== 'areas' && kind !== 'materials' && m.size < 4) {
        const core = new Set();
        st.sectors.forEach(sid => (SEC.get(sid) ? SEC.get(sid).r : []).forEach(r => core.add(r)));
        [...POOL[kind].values()].map(x => [x, x.r.filter(r => core.has(r)).length]).filter(([, n]) => n >= 2)
          .sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([x]) => add(x.id, 'Faaliyetin riskleriyle ilişkili'));
      }
      return m;
    }
    /** Analize girecek kayıtlar ve her birini getiren seçimler. */
    function candidates(st) {
      const F = features(st);
      const src = new Map();
      const add = (ids, why) => (ids || []).forEach(id => { if (!RISK.has(id)) return; if (!src.has(id)) src.set(id, new Set()); src.get(id).add(why); });
      const sectorExcluded = new Set();
      st.sectors.forEach(sid => { const s = SEC.get(sid); if (!s) return; add(s.r, s.n); s.x.forEach(x => sectorExcluded.add(x)); });
      chosenOptions(st).forEach(o => { add(o.r, o.l); o.is.forEach(sid => { const s = SEC.get(sid); if (s) add(s.r.filter(r => !s.x.includes(r)), o.l); }); });
      [['areas', AREA], ['equipment', EQ], ['tasks', TASK], ['materials', MAT]].forEach(([k, pool]) => (st[k] || []).forEach(id => { const x = pool.get(id); if (x) add(x.r, x.n); }));
      F.forEach(f => add(D.fr[f], D.cond[f] || 'Seçimlerinizden'));
      add(D.mg, 'Genel konular');
      for (const [id, why] of [...src]) {
        const r = RISK.get(id);
        if (r.req.length && !r.req.some(x => F.has(x))) src.delete(id);
        else if (sectorExcluded.has(id) && why.size === 1) src.delete(id);
        else if (r.fam === 'G53' && (st.mgmtOff || []).includes(id)) src.delete(id);
      }
      return src;
    }
    /** "Genel konular" adımında gösterilecek yönetim maddeleri. */
    function managementItems(st) {
      const F = features(st);
      const ids = new Set(D.mg);
      Object.entries(D.fr).forEach(([f, list]) => { if (F.has(f)) list.forEach(id => { const r = RISK.get(id); if (r && r.fam === 'G53') ids.add(id); }); });
      return [...ids].map(id => RISK.get(id)).filter(r => r && (!r.req.length || r.req.some(x => F.has(x))));
    }
    /** Önerilen skor + kullanıcı düzenlemesi; 5×5 elle girilmedikçe FK'dan türetilir. */
    function scoreOf(st, r) {
      const e = (st.edits && st.edits[r.id]) || {};
      const [s, p, f, rp, rf, rs] = r.s;
      const fk = {p: e.p != null ? e.p : p, f: e.f != null ? e.f : f, s: e.s != null ? e.s : SFK[s]};
      const rfk = {p: e.rp != null ? e.rp : rp, f: e.rf != null ? e.rf : rf, s: e.rs != null ? e.rs : SFK[rs]};
      const m5 = e.m5 || {l: L5(fk.p * fk.f), s: FK2M5[fk.s]};
      const rm5 = e.rm5 || {l: L5(rfk.p * rfk.f), s: FK2M5[rfk.s]};
      return {fk, rfk, m5, rm5, edited: Object.keys(e).length > 0};
    }
    /** Sıralı satırlar: bölümler en yüksek riske göre, genel konular en sonda. */
    function rows(st) {
      const src = candidates(st);
      const list = [...src.keys()].map(id => RISK.get(id));
      const famMax = {};
      list.forEach(r => { famMax[r.fam] = Math.max(famMax[r.fam] || 0, fkR(scoreOf(st, r).fk)); });
      list.sort((a, b) => {
        if ((a.fam === 'G53') !== (b.fam === 'G53')) return a.fam === 'G53' ? 1 : -1;
        if (a.fam !== b.fam) return famMax[b.fam] - famMax[a.fam] || a.fam.localeCompare(b.fam);
        return fkR(scoreOf(st, b).fk) - fkR(scoreOf(st, a).fk) || a.id.localeCompare(b.id);
      });
      return list.map(r => ({r, why: [...src.get(r.id)]}));
    }
    /** RDReport.build girdisi. */
    function reportInput(st) {
      const removed = new Set(st.removed || []);
      const list = rows(st).filter(x => !removed.has(x.r.id));
      const hc = hazardClass(st);
      let validUntil = '';
      const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec((st.firm && st.firm.date) || '');
      if (m && hc) validUntil = m[1].padStart(2, '0') + '.' + m[2].padStart(2, '0') + '.' + (Number(m[3]) + RENEW[hc]);
      const firm = st.firm || {};
      return {
        firm: {name: firm.name, address: firm.address, sector: st.sectors.map(id => SEC.get(id).n).join(', '),
          nace: [...new Set(st.sectors.flatMap(id => SEC.get(id).nace))].join(', '), hazardClass: hc ? HC[hc] : '',
          employees: EMP[firm.employees] || '', date: firm.date, validUntil},
        method: st.method || 'both', columns: st.cols,
        rows: list.map(({r}) => {
          const s = scoreOf(st, r);
          return {section: D.fam[r.fam] || r.fam, hazard: r.hz, risk: r.sc, consequence: r.cs, affected: r.af, existing: '',
            controls: r.ctl.map(ct => ({label: HIER[ct[0]], text: ct[1], owner: D.roles[ct[2]] || ''})), owner: D.roles[r.own] || '',
            deadline: DEADLINE[fkLevel(fkR(s.fk))[2]], legal: r.lg.map(x => D.legal[x] || x), fk: s.fk, rfk: s.rfk, m5: s.m5, rm5: s.rm5};
        }),
      };
    }
    return {RISK, SEC, AREA, EQ, TASK, MAT, FU, POOL, hazardClass, answered, activeFollowups, applyDefaults, chosenOptions,
      features, suggestions, candidates, managementItems, scoreOf, rows, reportInput};
  }

  root.RDEngine = {create, SFK, FK2M5, L5, fkR, m5R, fkLevel, m5Level, HC, HIER, EMP, RENEW, DEADLINE, FK_LEVELS, M5_LEVELS};
  if (typeof module !== 'undefined' && module.exports) module.exports = root.RDEngine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
