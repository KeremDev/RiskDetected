/*
 * RDEmergency — acil durum planı sihirbazının seçim motoru ve belge üreticisi (V6 katalog).
 *
 * Risk sihirbazıyla aynı cevapları (faaliyet, takip soruları, alan/ekipman/madde/iş, çalışma düzeni) kullanır;
 * RDEngine.features() çıktısına göre senaryo kartlarını seçer. Saf fonksiyonlar: DOM, ağ ve saat kullanmaz.
 *
 * Mevzuat sayıları (kaynak: İşyerlerinde Acil Durumlar Hakkında Yönetmelik, 18.06.2013/28681;
 * değişiklik 01.10.2021/31615; İlkyardım Yönetmeliği 29.07.2015/29429, değişiklik 27.12.2025/33120):
 *   - Plan yenileme: çok tehlikeli 2, tehlikeli 4, az tehlikeli 6 yıl (m.14/2).
 *   - Söndürme, kurtarma, koruma ekiplerinin her biri için her 30/40/50 çalışana kadar en az birer destek elemanı,
 *     katlar dâhil (m.11/3); 10'dan az çalışanda üç ekip için en az bir destek elemanı yeterli (m.11/4).
 *   - İlk yardım ekibi İlkyardım Yönetmeliğine göre: her 10/15/20 çalışana kadar bir ilkyardımcı (yukarı yuvarlanır).
 *   - Tatbikat en geç yılda bir; maden işyerlerinde Maden İSG Yönetmeliği (m.13/2).
 * Hesap bir referanstır; kişilerin eğitimi, vardiya kapsaması ve görev çakışması ayrıca değerlendirilir.
 *
 * state.em = {employees: sayı|null, site: [koşul], off: [kart], extra: [kart], fields: {anahtar: metin},
 *             team: [{role, name, title, area, contact, backup}], contacts: [{label, number}]}
 */
(function (root) {
  'use strict';

  const RENEW = {high: 2, medium: 4, low: 6};
  const TEAM_DIV = {high: 30, medium: 40, low: 50};
  const FIRST_AID_DIV = {high: 10, medium: 15, low: 20};
  const HC = {low: 'Az tehlikeli', medium: 'Tehlikeli', high: 'Çok tehlikeli'};
  const ROLES = [
    {id: 'sondurme', label: 'Söndürme ekibi', duty: 'Yangına derhal müdahale ederek mümkünse kontrol altına almak, yayılmasını önlemek ve söndürme faaliyetlerini yürütmek.'},
    {id: 'kurtarma', label: 'Kurtarma ekibi', duty: 'Acil durum sonrası çalışanların, ziyaretçilerin ve diğer kişilerin arama ve kurtarma işlerini yürütmek.'},
    {id: 'koruma', label: 'Koruma ekibi', duty: 'Panik ve kargaşayı önlemek, ekipler arası koordinasyonu ve sayımı yürütmek, gerektiğinde resmî müdahale ekiplerine bilgi vermek.'},
    {id: 'ilkyardim', label: 'İlk yardım ekibi', duty: 'Acil durumdan etkilenen kişilere ilk yardım uygulamak.'},
  ];
  const ROLE = Object.fromEntries(ROLES.map(r => [r.id, r]));
  const GENERAL_FIELDS = [
    {key: 'employer', label: 'İşveren / işveren vekili'},
    {key: 'preparers', label: 'Planı hazırlayanlar (ad, soyad, unvan)'},
    {key: 'assembly_point', label: 'Toplanma yeri'},
    {key: 'alarm', label: 'Alarm şekli ve alarm butonlarının yerleri'},
    {key: 'shutoff', label: 'Elektrik ve gaz kesme noktaları, vanalar'},
    {key: 'first_aid_kit', label: 'İlk yardım dolabı / çantası yeri'},
    {key: 'extinguishers', label: 'Yangın söndürme ekipmanlarının yerleri'},
    {key: 'exits', label: 'Kaçış yolları ve güvenli çıkışlar'},
    {key: 'ambulance_access', label: 'Ambulans ve itfaiye yaklaşım / karşılama noktası'},
  ];
  // Kartlardaki saha anahtarlarından ortak bilgiye karşılık gelenler bir kez sorulur (null: başka yerden gelir).
  const FIELD_ALIAS = {
    toplanma: 'assembly_point', toplanma_yeri: 'assembly_point', alarm_noktasi: 'alarm', alarm_talimat: 'alarm',
    guvenli_enerji_kesme_noktasi: 'shutoff', tesisat_kesme: 'shutoff', sondurucu_turu_yeri: 'extinguishers',
    ilkyardim_kiti: 'first_aid_kit', guvenli_cikis: 'exits', alternatif_cikis: 'exits',
    ambulans_karsilama: 'ambulance_access', ambulans_erisim: 'ambulance_access', acik_adres: null, ilkyardimci: null,
  };
  const DEFAULT_CONTACTS = [{label: 'Acil çağrı (ambulans, itfaiye, polis, AFAD)', number: '112'}];
  const CEIL = (n, d) => Math.max(1, Math.ceil(n / d));

  function create(D, E) {
    const EM = D.em || {cards: [], site: []};
    const CARD = new Map(EM.cards.map(c => [c.id, c]));
    const SITE = new Map(EM.site.map(s => [s.id, s]));

    function em(st) {
      st.em = st.em || {};
      const e = st.em;
      e.site = e.site || []; e.off = e.off || []; e.extra = e.extra || []; e.fields = e.fields || {};
      e.team = e.team || []; e.contacts = e.contacts || DEFAULT_CONTACTS.map(c => Object.assign({}, c));
      if (e.employees === undefined) e.employees = null;
      return e;
    }

    /** Kartları getiren özellik → okunur gerekçe (ör. "LPG otogaz", "Asetilen tüpü"). */
    function reasonsFor(st, card, F) {
      const hits = card.req.filter(f => F.has(f));
      if (!hits.length) return [];
      const out = [];
      const add = t => { if (t && !out.includes(t)) out.push(t); };
      const has = (fs) => (fs || []).some(f => hits.includes(f) || (D.fi[f] || []).some(x => hits.includes(x)));
      st.sectors.forEach(id => { const s = E.SEC.get(id); if (s && has(s.f)) add(s.n); });
      E.activeFollowups(st).forEach(f => E.answered(st, f.id).forEach(oid => {
        const o = f.o.find(x => x.id === oid);
        if (!o || !has(o.f)) return;
        // "Evet" gibi kısa cevaplar tek başına bir şey anlatmaz; sorunun kendisi gerekçe olur.
        const q = f.q.replace(/\?$/, '');
        add(o.l.length <= 12 ? (q.length > 48 ? q.slice(0, 47) + '…' : q) + ': ' + o.l : o.l);
      }));
      [['equipment', E.EQ], ['tasks', E.TASK], ['materials', E.MAT]].forEach(([k, pool]) => (st[k] || []).forEach(id => { const x = pool.get(id); if (x && has(x.f)) add(x.n); }));
      (st.cond || []).forEach(id => { if (hits.includes(id)) add(D.cond[id]); });
      em(st).site.forEach(id => { if (hits.includes(id) && SITE.has(id)) add(SITE.get(id).l); });
      (st.areas || []).forEach(id => { if (hits.includes(id)) add((E.AREA.get(id) || {}).n); });
      return out.length ? out : ['Seçimlerinizden'];
    }

    function features(st) {
      const F = E.features(st);
      const extra = em(st).site;
      if (!extra.length) return F;
      extra.forEach(x => F.add(x));
      let grew = true;
      while (grew) { grew = false; [...F].forEach(x => (D.fi[x] || []).forEach(y => { if (!F.has(y)) { F.add(y); grew = true; } })); }
      return F;
    }

    /** Önerilen kartlar (çekirdek + özelliğe uyan) ve kullanıcı eklemeleri/çıkarmaları. */
    function cards(st) {
      const e = em(st);
      const F = features(st);
      const list = [];
      EM.cards.forEach(c => {
        const suggested = !!c.core || c.req.some(f => F.has(f));
        const added = e.extra.includes(c.id);
        if (!suggested && !added) return;
        list.push({card: c, core: !!c.core, suggested, why: c.core ? ['Her planda'] : suggested ? reasonsFor(st, c, F) : ['Elle eklendi'],
          selected: !!c.core || (suggested ? !e.off.includes(c.id) : true)});
      });
      list.sort((a, b) => (b.core - a.core) || (b.suggested - a.suggested) || a.card.id.localeCompare(b.card.id));
      return list;
    }
    const selectedCards = st => cards(st).filter(x => x.selected);

    /** Destek elemanı ve ilkyardımcı referans hesabı. */
    function teams(st) {
      const e = em(st);
      const hc = E.hazardClass(st);
      const n = Number.isFinite(e.employees) && e.employees > 0 ? Math.floor(e.employees) : null;
      const assigned = id => e.team.filter(m => m.role === id && !m.backup && (m.name || '').trim()).length;
      const base = {hazardClass: hc, hazardClassLabel: hc ? HC[hc] : '', employees: n, validYears: hc ? RENEW[hc] : null,
        small: n != null && n < 10, drill: 'En geç yılda bir tatbikat (maden işyerlerinde Maden İSG Yönetmeliğine göre).'};
      const roles = ROLES.map(r => {
        let required = null, basis = '';
        if (hc && n != null) {
          if (r.id === 'ilkyardim') { required = CEIL(n, FIRST_AID_DIV[hc]); basis = 'Her ' + FIRST_AID_DIV[hc] + ' çalışana kadar 1 ilkyardımcı (İlkyardım Yönetmeliği)'; }
          else if (n < 10) { required = null; basis = '10\'dan az çalışan: söndürme, kurtarma ve koruma için en az 1 destek elemanı yeterli'; }
          else { required = CEIL(n, TEAM_DIV[hc]); basis = 'Her ' + TEAM_DIV[hc] + ' çalışana kadar 1 destek elemanı'; }
        } else basis = hc ? 'Çalışan sayısı girilince hesaplanır' : 'Tehlike sınıfı ve çalışan sayısı girilince hesaplanır';
        return {id: r.id, label: r.label, duty: r.duty, required, assigned: assigned(r.id), basis};
      });
      const combined = base.small ? {required: 1, assigned: e.team.filter(m => ['sondurme', 'kurtarma', 'koruma'].includes(m.role) && !m.backup && (m.name || '').trim())
        .map(m => m.name.trim()).filter((v, i, a) => a.indexOf(v) === i).length} : null;
      return Object.assign(base, {roles, combined,
        note: 'Referans ekip hesabıdır; kişilerin eğitimini, vardiya kapsamasını ve görev çakışmasını doğrulamaz. Rol sayılarının toplamı farklı kişi sayısı değildir.'});
    }

    /** Saha bilgileri: önce ortak alanlar, sonra seçili kartlara özgü alanlar (kart başlığıyla). */
    function siteFields(st) {
      const e = em(st);
      const out = GENERAL_FIELDS.map(f => ({key: f.key, label: f.label, value: e.fields[f.key] || '', general: true, card: ''}));
      const seen = new Set(out.map(f => f.key));
      selectedCards(st).forEach(({card}) => Object.entries(card.sf || {}).forEach(([k, l]) => {
        if (k in FIELD_ALIAS || seen.has(k)) return;
        seen.add(k);
        out.push({key: k, label: l, value: e.fields[k] || '', general: false, card: card.t});
      }));
      return out;
    }
    /** Kart üzerinde gösterilecek saha bilgileri (ortak alana bağlı olanlar oradan dolar). */
    function cardFields(st, card) {
      const e = em(st);
      const labels = new Map(GENERAL_FIELDS.map(f => [f.key, f.label]));
      const out = [];
      Object.entries(card.sf || {}).forEach(([k, l]) => {
        const g = FIELD_ALIAS[k];
        if (g === null) return;
        const key = g || k;
        if (out.some(f => f.key === key)) return;
        out.push({key, label: g ? labels.get(g) : l, value: e.fields[key] || ''});
      });
      return out;
    }
    function gaps(st) {
      const e = em(st);
      const out = [];
      if (!(st.firm.name || '').trim()) out.push('İşyerinin unvanı');
      if (!(st.firm.address || '').trim()) out.push('İşyerinin adresi');
      if (!E.hazardClass(st)) out.push('Tehlike sınıfı');
      if (e.employees == null) out.push('Çalışan sayısı (ekip hesabı için)');
      const fields = siteFields(st);
      fields.filter(f => f.general).forEach(f => { if (!f.value.trim()) out.push(f.label); });
      const cardBlank = fields.filter(f => !f.general && !f.value.trim()).length;
      if (cardBlank) out.push('Eylem kartlarına özgü ' + cardBlank + ' saha bilgisi (kartlarda boş bırakıldı)');
      const t = teams(st);
      if (t.combined && t.combined.assigned < 1) out.push('Söndürme, kurtarma ve koruma için destek elemanı');
      t.roles.forEach(r => { if (r.required != null && r.assigned < r.required) out.push(r.label + ': ' + (r.required - r.assigned) + ' kişi daha (referans)'); });
      if (!e.contacts.some(c => c.number && c.number.trim() !== '112')) out.push('Yerel kurum ve kuruluşların irtibat numaraları');
      out.push('Tahliye planı / kroki (kaçış yolları, toplanma yeri, söndürücü ve ilk yardım malzemesi yerleri)');
      return out;
    }

    function validUntil(st) {
      const hc = E.hazardClass(st);
      const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec((st.firm && st.firm.date) || '');
      return m && hc ? m[1].padStart(2, '0') + '.' + m[2].padStart(2, '0') + '.' + (Number(m[3]) + RENEW[hc]) : '';
    }

    /** Belge girdisi: tüm bölümler düz veri. */
    function planInput(st) {
      const e = em(st);
      const hc = E.hazardClass(st);
      const sel = selectedCards(st);
      return {
        firm: {name: st.firm.name || '', address: st.firm.address || '', date: st.firm.date || '', validUntil: validUntil(st), hazardClassId: hc || '',
          sector: st.sectors.map(id => E.SEC.get(id).n).join(', '), nace: [...new Set(st.sectors.flatMap(id => E.SEC.get(id).nace))].join(', '),
          hazardClass: hc ? HC[hc] : '', employees: e.employees == null ? '' : String(e.employees)},
        profile: {
          areas: (st.areas || []).map(id => (E.AREA.get(id) || {}).n).filter(Boolean),
          equipment: (st.equipment || []).map(id => (E.EQ.get(id) || {}).n).filter(Boolean),
          materials: (st.materials || []).map(id => (E.MAT.get(id) || {}).n).filter(Boolean),
          conditions: (st.cond || []).map(id => D.cond[id]).filter(Boolean).concat(e.site.map(id => (SITE.get(id) || {}).l).filter(Boolean)),
        },
        cards: sel.map(({card, why, core}) => ({id: card.id, title: card.t, trigger: card.tr, mode: card.ml, core, why,
          before: card.b, worker: card.dw, team: card.dt, prohibited: card.pr, after: card.a, reentry: card.re,
          siteFields: cardFields(st, card), legal: (card.lg || []).map(x => D.legal[x] || x)})),
        teams: teams(st),
        members: e.team.filter(m => (m.name || '').trim()).map(m => ({role: (ROLE[m.role] || {}).label || m.role, roleId: m.role, ref: m.ref || null,
          name: m.name.trim(), title: m.title || '', area: m.area || '', contact: m.contact || '', backup: !!m.backup})),
        contacts: e.contacts.filter(c => (c.label || c.number)),
        fields: siteFields(st),
        gaps: gaps(st),
      };
    }

    return {CARD, SITE, ROLES, GENERAL_FIELDS, em, cardFields, features, cards, selectedCards, teams, siteFields, gaps, validUntil, planInput};
  }

  /* ---------------------------------------------------------------- belge */

  const xmlEsc = s => String(s == null ? '' : s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const blank = v => (v && String(v).trim()) ? v : '……………… (sahada tamamlanacak)';

  /** Word (.docx), A4 dikey. `only: 'cards'` yalnız eylem kartlarını üretir (her kart ayrı sayfa). */
  function docx(input, opts) {
    opts = opts || {};
    const X = root.RDXlsx;
    const run = (t, o) => {
      o = o || {};
      const rp = (o.b ? '<w:b/>' : '') + (o.i ? '<w:i/>' : '') + '<w:sz w:val="' + (o.sz || 20) + '"/>' + (o.color ? '<w:color w:val="' + o.color + '"/>' : '');
      return String(t).split('\n').map((line, i) => (i ? '<w:r><w:br/></w:r>' : '') + '<w:r><w:rPr>' + rp + '</w:rPr><w:t xml:space="preserve">' + xmlEsc(line) + '</w:t></w:r>').join('');
    };
    const p = (t, o) => { o = o || {}; return '<w:p><w:pPr>' + (o.pageBreak ? '<w:pageBreakBefore/>' : '') + (o.keep ? '<w:keepNext/>' : '') +
      '<w:spacing w:before="' + (o.before || 0) + '" w:after="' + (o.after == null ? 80 : o.after) + '"/>' + (o.ind ? '<w:ind w:left="' + o.ind + '" w:hanging="220"/>' : '') + '</w:pPr>' + run(t, o) + '</w:p>'; };
    const h1 = (t, o) => p(t, Object.assign({b: true, sz: 26, before: 240, after: 100, keep: true, color: '0B2F53'}, o || {}));
    const h2 = t => p(t, {b: true, sz: 21, before: 140, after: 60, keep: true});
    const bullets = list => (list || []).map(x => p('•  ' + x, {ind: 360, after: 40})).join('');
    const cell = (t, w, o) => { o = o || {};
      return '<w:tc><w:tcPr><w:tcW w:w="' + w + '" w:type="dxa"/>' + (o.span ? '<w:gridSpan w:val="' + o.span + '"/>' : '') + (o.fill ? '<w:shd w:val="clear" w:color="auto" w:fill="' + o.fill + '"/>' : '') +
        '</w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr>' + run(t, {sz: o.sz || 18, b: o.b, color: o.color}) + '</w:p></w:tc>'; };
    const table = (widths, rows) => '<w:tbl><w:tblPr><w:tblW w:w="' + widths.reduce((a, b) => a + b, 0) + '" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>' +
      ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map(x => '<w:' + x + ' w:val="single" w:sz="4" w:color="C9D1CD"/>').join('') +
      '</w:tblBorders><w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="90" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar></w:tblPr>' +
      '<w:tblGrid>' + widths.map(w => '<w:gridCol w:w="' + w + '"/>').join('') + '</w:tblGrid>' + rows + '</w:tbl>' + p('', {after: 60});
    const tr = (cells, header) => '<w:tr><w:trPr><w:cantSplit/>' + (header ? '<w:tblHeader/>' : '') + '</w:trPr>' + cells + '</w:tr>';
    const head = (labels, widths) => tr(labels.map((t, i) => cell(t, widths[i], {b: true, fill: '0B2F53', color: 'FFFFFF'})).join(''), true);
    const kv = (rows, w1, w2) => table([w1, w2], rows.map(([k, v]) => tr(cell(k, w1, {b: true, fill: 'EEF2F0'}) + cell(v, w2))).join(''));
    const W = 9900;
    const firm = input.firm || {};

    function cardPage(c, n, pageBreak) {
      let s = p('ACİL DURUM EYLEM KARTI · ' + c.id + (firm.name ? ' · ' + firm.name : ''), {sz: 16, color: '6B7280', pageBreak, after: 40});
      s += p(n + '. ' + c.title, {b: true, sz: 30, after: 60, color: '9F1D1D'});
      s += kv([['Ne zaman', c.trigger], ['Müdahale türü', c.mode]], 2200, W - 2200);
      s += h2('Çalışan ne yapar'); s += bullets(c.worker);
      s += h2('Görevli ekip ne yapar'); s += bullets(c.team);
      s += h2('Yapılmayacaklar'); s += bullets(c.prohibited);
      if (c.siteFields.length) { s += h2('Bu işyerinde'); s += kv(c.siteFields.map(f => [f.label, blank(f.value)]), 3600, W - 3600); }
      s += p('Geri dönüş / yeniden giriş: ' + c.reentry, {sz: 17, i: true, before: 60});
      return s;
    }

    let body = '';
    if (opts.only === 'cards') {
      (input.cards || []).forEach((c, i) => { body += cardPage(c, i + 1, i > 0); });
    } else {
      body += p('ACİL DURUM PLANI', {b: true, sz: 40, after: 60, color: '0B2F53'});
      body += p(firm.name || 'İşyeri unvanı: ……………………', {b: true, sz: 28, after: 200});
      body += kv([
        ['İşyerinin unvanı', blank(firm.name)], ['Adresi', blank(firm.address)], ['İşveren / işveren vekili', blank((input.fields.find(f => f.key === 'employer') || {}).value)],
        ['Faaliyet', firm.sector || '—'], ['NACE', firm.nace || '—'], ['Tehlike sınıfı', blank(firm.hazardClass)], ['Çalışan sayısı', blank(firm.employees)],
        ['Hazırlayanlar', blank((input.fields.find(f => f.key === 'preparers') || {}).value)], ['Hazırlandığı tarih', blank(firm.date)],
        ['Geçerlilik tarihi', firm.validUntil ? firm.validUntil + ' (' + input.teams.validYears + ' yıl; değişiklik hâlinde daha önce yenilenir)' : blank('')],
      ], 3000, W - 3000);
      body += p('Plan işveren tarafından onaylanır; sayfaları numaralanarak hazırlayanlarca her sayfası paraflanır ve son sayfası imzalanır. Plan, ekiplerin kolayca ulaşabileceği yerde saklanır.', {sz: 17, color: '6B7280'});

      body += h1('1. Amaç ve kapsam', {pageBreak: true});
      body += p('Bu plan, işyerinde meydana gelebilecek veya işyerini dışarıdan etkileyebilecek acil durumlarda yapılacak iş ve işlemleri, ekiplerin görevlerini, haberleşme ve tahliye düzenini belirler. 6331 sayılı İş Sağlığı ve Güvenliği Kanunu ile İşyerlerinde Acil Durumlar Hakkında Yönetmelik esas alınmıştır. Acil durumlar, risk değerlendirmesinin sonuçları dikkate alınarak belirlenmiştir.');
      body += p('Plan; işyerindeki çalışanları, varsa alt işveren ve geçici iş ilişkisiyle çalışanları, müşteri ve ziyaretçileri ve toplu faaliyetlere katılanları kapsar.');
      body += h1('2. İşyeri profili');
      const pr = input.profile || {};
      body += kv([['Faaliyet', firm.sector || '—'], ['Çalışma alanları', pr.areas.join(', ') || '—'], ['Kritik ekipman', pr.equipment.slice(0, 25).join(', ') || '—'],
        ['Tehlikeli maddeler', pr.materials.join(', ') || '—'], ['Çalışma düzeni ve saha koşulları', pr.conditions.join(', ') || '—']], 3000, W - 3000);
      body += h1('3. Belirlenen acil durumlar');
      const w3 = [600, 3100, 3700, 2500];
      body += table(w3, head(['No', 'Acil durum', 'Ne zaman devreye girer', 'Belirleme gerekçesi'], w3) +
        input.cards.map((c, i) => tr(cell(String(i + 1), w3[0]) + cell(c.title + '\n' + c.mode, w3[1]) + cell(c.trigger, w3[2]) + cell(c.why.join(', '), w3[3]))).join(''));
      body += h1('4. Önleyici ve sınırlandırıcı tedbirler');
      body += p('Aşağıdaki hazırlık tedbirleri her acil durum için olay öncesinde yerine getirilir; plan, bu tedbirlerin uygulandığı anlamına gelmez.', {sz: 18, color: '6B7280'});
      input.cards.forEach((c, i) => { body += h2((i + 1) + '. ' + c.title); body += bullets(c.before); });
      body += h1('5. Acil durum ekipleri ve görevleri');
      const t = input.teams;
      body += p('Tehlike sınıfı: ' + (t.hazardClassLabel || '—') + ' · Çalışan sayısı: ' + (t.employees == null ? '—' : t.employees), {b: true});
      const w5 = [2400, 4600, 1400, 1500];
      body += table(w5, head(['Ekip', 'Görevi', 'Referans', 'Atanan'], w5) + t.roles.map(r => tr(cell(r.label, w5[0], {b: true}) + cell(r.duty + '\n' + r.basis, w5[1], {sz: 16}) +
        cell(r.required == null ? (t.combined && r.id !== 'ilkyardim' ? '1 (ortak)' : '—') : String(r.required), w5[2]) + cell(String(r.assigned), w5[3]))).join(''));
      body += p(t.note, {sz: 16, i: true, color: '6B7280'});
      body += p('Her ekipte bir ekip başı bulunur; ekipler arası koordinasyon için koruma ekibinden sorumlu görevlendirilir. Destek elemanları ve yedekleri vardiya düzeni dikkate alınarak belirlenir; ayrılma veya yer değişikliğinde yeniden görevlendirme yapılır. Ekip listesi (ad, soyad, unvan, sorumluluk alanı, iletişim) çalışanların görebileceği yükseklikte asılır.', {sz: 18});
      const w6 = [1900, 2300, 1700, 2000, 2000];
      const members = input.members.length ? input.members : [];
      body += h2('Görevlendirilen destek elemanları');
      body += table(w6, head(['Ekip', 'Adı soyadı', 'Unvan', 'Sorumluluk alanı', 'İletişim'], w6) +
        (members.length ? members.map(m => tr(cell(m.role + (m.backup ? ' (yedek)' : ''), w6[0]) + cell(m.name, w6[1]) + cell(m.title, w6[2]) + cell(m.area, w6[3]) + cell(m.contact, w6[4]))).join('')
          : ROLES.map(r => tr(cell(r.label, w6[0]) + cell('', w6[1]) + cell('', w6[2]) + cell('', w6[3]) + cell('', w6[4]))).join('')));
      body += h1('6. Alarm ve haberleşme');
      const fv = k => (input.fields.find(f => f.key === k) || {}).value;
      body += kv([['Alarm şekli ve butonları', blank(fv('alarm'))], ['Elektrik ve gaz kesme noktaları, vanalar', blank(fv('shutoff'))]], 3600, W - 3600);
      const w7 = [6400, 3500];
      body += h2('Acil durum irtibat numaraları');
      body += table(w7, head(['Kurum / kişi', 'Numara'], w7) + input.contacts.map(c => tr(cell(c.label, w7[0]) + cell(c.number, w7[1]))).join('') +
        ['Yerel itfaiye / AFAD il müdürlüğü', 'En yakın sağlık kuruluşu', 'Doğal gaz / elektrik dağıtım arıza', 'İşveren / işveren vekili'].filter(l => !input.contacts.some(c => c.label === l)).map(l => tr(cell(l, w7[0]) + cell('', w7[1]))).join(''));
      body += h1('7. Tahliye, toplanma ve sayım');
      body += bullets(['Tahliye kararı alarmla duyurulur; çalışanlar en yakın güvenli çıkıştan, asansör kullanmadan toplanma yerine gider.',
        'Koruma ekibi toplanma yerinde sayım yapar; eksik kişinin son bilinen yeri resmî ekiplere bildirilir, kimse arama için geri gönderilmez.',
        'Yaşlı, engelli ve gebe çalışanlar ile varsa kreşteki çocuklara tahliyede refakat edecek kişiler önceden belirlenir.',
        'Ziyaretçi ve alt işveren çalışanları sayıma dâhil edilir.',
        'Yakındaki işyerlerinden ve çevreden gelebilecek etkiler tahliye yönünü ve toplanma yerini belirlerken dikkate alınır.']);
      body += kv([['Toplanma yeri', blank(fv('assembly_point'))], ['Yangın söndürme ekipmanlarının yerleri', blank(fv('extinguishers'))], ['İlk yardım malzemesi yeri', blank(fv('first_aid_kit'))]], 3600, W - 3600);
      body += h1('8. Acil durum müdahale yöntemleri');
      input.cards.forEach((c, i) => {
        body += h2((i + 1) + '. ' + c.title + ' — ' + c.mode);
        body += p('Ne zaman: ' + c.trigger, {sz: 18, i: true});
        body += p('Çalışan', {b: true, sz: 18, after: 30}); body += bullets(c.worker);
        body += p('Görevli ekip', {b: true, sz: 18, after: 30}); body += bullets(c.team);
        body += p('Yapılmayacaklar', {b: true, sz: 18, after: 30}); body += bullets(c.prohibited);
        body += p('Olay sonrası', {b: true, sz: 18, after: 30}); body += bullets(c.after);
        body += p('Yeniden giriş: ' + c.reentry, {sz: 17, i: true});
      });
      body += h1('9. Dış kuruluşlarla koordinasyon');
      body += bullets(['Resmî müdahale ekipleri geldiğinde olay yeri, etkilenen kişi sayısı, tehlikeli maddeler ve kesme noktaları hakkında koruma ekibi sorumlusu bilgi verir.',
        'İşyerinin giriş yolu, itfaiye ve ambulans yaklaşım noktası açık tutulur.',
        'Olay yönetimi resmî ekiplere geçtikten sonra işyeri ekipleri onların talimatıyla hareket eder.']);
      body += h1('10. Eğitim ve tatbikat');
      body += bullets(['Tüm çalışanlar acil durum planı ve destek elemanları hakkında bilgilendirilir; işe yeni başlayan ve geçici çalışanlara ayrıca bilgi verilir.',
        'Söndürme, kurtarma ve koruma ekipleri görevlerine yönelik özel eğitim alır; ilk yardım ekibi İlkyardım Yönetmeliğine göre ilkyardımcı belgesine sahip olur.',
        t.drill, 'Her tatbikatta tarih, görülen eksiklikler ve yapılacak düzenlemeler tatbikat formuna yazılır.']);
      const w9 = [1800, 3600, 4500];
      body += table(w9, head(['Tarih', 'Senaryo', 'Görülen eksiklikler ve düzenlemeler'], w9) + [1, 2, 3].map(() => tr(cell('', w9[0]) + cell('', w9[1]) + cell('', w9[2]))).join(''));
      body += h1('11. Gözden geçirme ve yenileme');
      body += p('Plan, geçerlilik tarihinden önce ve işyerinde acil durumları etkileyebilecek bir değişiklik olduğunda (yeni bina/bölüm, yeni tehlikeli madde veya ekipman, süreç değişikliği, tatbikat veya gerçek olayda görülen eksiklik) yenilenir. Olay sonrası normal faaliyete dönüş, ilgili kartın yeniden giriş koşulu sağlandıktan sonra yapılır.');
      body += h1('Ek-1. Sahada tamamlanacak bilgiler', {pageBreak: true});
      body += p('Aşağıdaki bilgiler sahada doğrulanmadan plan tamamlanmış sayılmaz. Sistem saha bilgisi üretmez.', {sz: 18, color: '6B7280'});
      body += bullets(input.gaps);
      body += h1('Ek-2. Tahliye planı / kroki');
      body += p('Kaçış yolları, toplanma yerleri, yangın söndürme ekipmanları, ilk yardım malzemeleri, tehlikeli bölümler ve elektrik/gaz kesme noktalarını gösteren tahliye planı bu sayfaya eklenir ve bina giriş-çıkışları ile katlarda asılır.', {sz: 18});
      body += table([W], tr(cell('\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n', W)));
      body += h1('Ek-3. Acil durum eylem kartları');
      body += p('Kartlar ayrı sayfalarda basılıp ilgili bölümlere asılabilir.', {sz: 18, color: '6B7280'});
      (input.cards || []).forEach((c, i) => { body += cardPage(c, i + 1, true); });
      body += p('', {after: 200});
      body += p('Onaylayan işveren / işveren vekili: ……………………………   İmza: ……………   Tarih: ……………', {before: 400, b: true});
    }

    const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    const footer = declaration + '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="center"/></w:pPr>' +
      run((opts.only === 'cards' ? 'Acil durum eylem kartları' : 'Acil durum planı') + (firm.name ? ' · ' + firm.name : '') + ' · Sayfa ', {sz: 16, color: '6B7280'}) +
      '<w:r><w:rPr><w:sz w:val="16"/><w:color w:val="6B7280"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>' +
      run(' / ', {sz: 16, color: '6B7280'}) +
      '<w:r><w:rPr><w:sz w:val="16"/><w:color w:val="6B7280"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>' +
      (opts.only === 'cards' ? '' : run('   ·   Paraf: ………', {sz: 16, color: '6B7280'})) + '</w:p></w:ftr>';
    const files = {
      '[Content_Types].xml': declaration + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>',
      '_rels/.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/_rels/document.xml.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>',
      'word/styles.xml': declaration + '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="20"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>',
      'word/footer1.xml': footer,
      'word/document.xml': declaration + '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + body +
        '<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="900" w:right="1000" w:bottom="900" w:left="1000" w:header="400" w:footer="400"/></w:sectPr></w:body></w:document>',
    };
    return X.zip(files);
  }

  /** PDF için metin blokları (yerel çiziciler: title, heading, subheading, text). */
  function blocks(input) {
    const firm = input.firm || {};
    const out = [{type: 'title', text: 'Acil Durum Planı' + (firm.name ? ' — ' + firm.name : '')},
      {type: 'text', text: ['Adres: ' + blank(firm.address), firm.sector && 'Faaliyet: ' + firm.sector, 'Tehlike sınıfı: ' + blank(firm.hazardClass),
        'Çalışan sayısı: ' + blank(firm.employees), 'Hazırlandığı tarih: ' + blank(firm.date), 'Geçerlilik: ' + blank(firm.validUntil)].filter(Boolean).join('\n')}];
    out.push({type: 'heading', text: 'Belirlenen acil durumlar'});
    out.push({type: 'text', text: input.cards.map((c, i) => (i + 1) + '. ' + c.title + ' (' + c.mode + ') — ' + c.why.join(', ')).join('\n')});
    out.push({type: 'heading', text: 'Acil durum ekipleri'});
    const t = input.teams;
    out.push({type: 'text', text: t.roles.map(r => r.label + ': referans ' + (r.required == null ? (t.combined && r.id !== 'ilkyardim' ? '1 (ortak)' : '—') : r.required) + ', atanan ' + r.assigned + ' · ' + r.basis).join('\n') + '\n' + t.note});
    if (input.members.length) out.push({type: 'text', text: input.members.map(m => m.role + (m.backup ? ' (yedek)' : '') + ': ' + m.name + (m.title ? ', ' + m.title : '') + (m.contact ? ' · ' + m.contact : '')).join('\n')});
    out.push({type: 'heading', text: 'İrtibat numaraları'});
    out.push({type: 'text', text: input.contacts.map(c => c.label + ': ' + c.number).join('\n')});
    out.push({type: 'heading', text: 'Müdahale yöntemleri'});
    input.cards.forEach((c, i) => {
      out.push({type: 'subheading', text: (i + 1) + '. ' + c.title + ' — ' + c.mode});
      out.push({type: 'text', text: 'Ne zaman: ' + c.trigger + '\nÖnce:\n' + c.before.map(x => '• ' + x).join('\n') + '\nÇalışan:\n' + c.worker.map(x => '• ' + x).join('\n') +
        '\nGörevli ekip:\n' + c.team.map(x => '• ' + x).join('\n') + '\nYapılmayacaklar:\n' + c.prohibited.map(x => '• ' + x).join('\n') +
        '\nSonra:\n' + c.after.map(x => '• ' + x).join('\n') + '\nYeniden giriş: ' + c.reentry});
    });
    out.push({type: 'heading', text: 'Sahada tamamlanacak bilgiler'});
    out.push({type: 'text', text: input.gaps.map(g => '• ' + g).join('\n')});
    out.push({type: 'text', text: t.drill + ' Plan, geçerlilik tarihinden önce ve acil durumları etkileyen değişikliklerde yenilenir.'});
    return out;
  }

  root.RDEmergency = {create, docx, blocks, RENEW, TEAM_DIV, FIRST_AID_DIV, ROLES};
  if (typeof module !== 'undefined' && module.exports) module.exports = root.RDEmergency;
})(typeof globalThis !== 'undefined' ? globalThis : this);
