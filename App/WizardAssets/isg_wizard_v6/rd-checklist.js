/*
 * RDChecklist — kontrol listesi sihirbazının seçim motoru ve belge üreticisi.
 *
 * Bu dosya katalog üreticisinin dışında, depoda tutulur (rd-bridge.js ve diğer rd-*.js dosyaları üretilir).
 * rd-bridge.js'den sonra yüklenir ve RDBridge'i sarar: yalnız start({mode: 'checklist'}) ile açılan oturumda
 * devreye girer; risk ve acil durum modlarında her çağrı değiştirilmeden asıl köprüye gider.
 *
 * Risk sihirbazıyla aynı cevapları (faaliyet, takip soruları, alan/ekipman/madde/iş, çalışma koşulları) kullanır;
 * RDEngine.features() çıktısına ve rd-checklist.json tetiklerine göre kontrol konularını (paketleri) önerir.
 * Saf fonksiyonlar: DOM, ağ ve saat kullanmaz.
 *
 *   RDBridge.init(dataText, checklistText)   → {version, …, checklistVersion, checklistPacks}
 *   RDBridge.start({name, date, mode: 'checklist'})
 *   RDBridge.act({type: 'ckPurpose'|'ckFreq'|'ckLayout'|'ckTitle'|'ckTopic'|'ckItem'|'ckItems'|'ckCustom', …})
 *   RDBridge.result()                        → liste girdisi (bölümler, kaydedilecek listeler)
 *   RDBridge.topics(q)                       → elle eklenebilecek konular
 *   RDBridge.file('docx'|'xlsx')  RDBridge.blocks()  RDBridge.fileName(ext)
 *
 * state (ck) = {purpose: 'site'|'preuse'|'task', freq: ''|'daily'|'weekly'|'monthly', layout: 'single'|'perTopic',
 *               title: '', off: [paket], extra: [paket], itemsOff: ['PAKET:sıra'], custom: [{pack, text}]}
 */
(function (root) {
  'use strict';
  const BASE = root.RDBridge;
  const ENG = root.RDEngine;
  if (!BASE || !ENG) return;

  let D = null, E = null, CK = null, PACK = null, on = false, C = null;

  const KIND_ORDER = ['general', 'sector', 'activity', 'equipment', 'hazard'];
  const PURPOSES = ['site', 'preuse', 'task'];
  const FREQS = ['daily', 'weekly', 'monthly'];
  const TR = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  const norm = s => String(s || '').toLocaleLowerCase('tr').replace(/i̇/g, 'i').replace(/[çğıöşüâîû]/g, c => TR[c] || c);
  const clone = x => JSON.parse(JSON.stringify(x));
  const toggle = (list, id) => { const i = list.indexOf(id); if (i >= 0) list.splice(i, 1); else list.push(id); };

  // Kontrol listesi sayfalarının metinleri katalogla gelir; iki platform aynı Türkçe metni gösterir.
  const TEXT = {
    title: 'Kontrol Listesi Sihirbazı',
    'step.firm': 'İşyeri', 'step.sector': 'Faaliyet', 'step.fu': 'Takip sorusu', 'step.areas': 'Çalışma alanları', 'step.equipment': 'Ekipmanlar',
    'step.materials': 'Maddeler', 'step.tasks': 'İşler', 'step.cond': 'Çalışma koşulları', 'step.purpose': 'Liste türü', 'step.topics': 'Konular',
    'step.items': 'Sorular', 'step.summary': 'Özet', 'step.result': 'Liste',
    'firm.title': 'Kontrol listesi hangi işyeri için?', 'firm.date': 'Liste tarihi',
    'firm.help': 'İsteğe bağlı; liste başlığında ve dosya adında kullanılır. Faaliyet ve ekipman seçimleri önerilecek konuları belirler.',
    'purpose.title': 'Liste ne için kullanılacak?',
    'purpose.help': 'Liste türü önerilecek konuları belirler. Sonraki adımda konuları tek tek açıp kapatabilirsiniz.',
    'purpose.site': 'Periyodik İSG saha denetimi', 'purpose.site.help': 'Faaliyet, alan, ekipman, iş ve her işyerindeki genel konular birlikte',
    'purpose.preuse': 'Ekipman kullanım öncesi kontrolü', 'purpose.preuse.help': 'Yalnız seçtiğiniz ekipmanlar için kısa, iş başı kontrolleri',
    'purpose.task': 'İş başlamadan önce kontrol', 'purpose.task.help': 'Sıcak iş, yüksekte çalışma, kapalı alan, kazı ve kaldırma gibi işlerin ön kontrolü',
    'freq.title': 'Kontrol sıklığı', 'freq.help': 'Seçerseniz genel saha turu listesi de eklenir. Sıklık yasal bir zorunluluk olarak yazılmaz.',
    'freq.none': 'Belirtilmedi', 'freq.daily': 'Günlük', 'freq.weekly': 'Haftalık', 'freq.monthly': 'Aylık',
    'layout.title': 'Liste düzeni', 'layout.single': 'Tek liste, konu başlıklarıyla', 'layout.perTopic': 'Her konu ayrı liste',
    'layout.help': 'Ayrı listeler, konuları farklı kişilerin veya farklı günlerde kontrol ettiği işyerleri için uygundur.',
    'topics.title': 'Hangi konular kontrol edilecek?',
    'topics.help': 'Önerilenler seçimlerinizden geliyor; gerekçesi altında yazıyor. İşyerinizde olmayan konuyu kapatın, eksik olanı arayarak ekleyin.',
    'topics.suggested': 'Önerilenler', 'topics.added': 'Eklediğiniz', 'topics.search': 'Başka konu ara (ör. forklift, iskele, kazan)',
    'topics.add': 'Başka konu ekle', 'topics.core': 'Her işyerinde', 'topics.manual': 'Elle eklendi', 'topics.freq': 'Seçilen sıklık',
    'topics.answers': 'Seçimlerinizden',
    'topics.empty': 'Bu seçimlerle önerilecek konu bulunamadı. Aşağıdan arayarak ekleyin.', 'topics.questions': 'soru', 'topics.new': 'Yeni',
    'topics.unit': 'konu',
    'topics.noHits': 'Bu aramayla konu bulunamadı. Daha genel bir kelime deneyin.',
    'kind.general': 'Genel tur', 'kind.sector': 'Faaliyet', 'kind.hazard': 'Tehlike', 'kind.activity': 'İş', 'kind.equipment': 'Ekipman',
    'items.title': 'Soruları gözden geçirin',
    'items.help': 'Her konudaki soruları açıp uygulanmayanları kaldırın. İşyerinize özgü sorunuzu konunun altına ekleyebilirsiniz.',
    'items.all': 'Tümünü seç', 'items.none': 'Tümünü kaldır', 'items.custom': 'Kendi sorunuzu ekleyin', 'items.placeholder': 'Soruyu yazın; “… mı?” biçiminde',
    'items.add': 'Ekle', 'items.own': 'Ek sorular', 'items.ownHelp': 'Belirli bir konuya bağlı olmayan sorular listenin sonuna eklenir.',
    'items.remove': 'Kaldır', 'items.empty': 'Önce en az bir konu seçin.', 'items.mine': 'Sizin sorunuz',
    'summary.title': 'Liste hazır', 'summary.help': 'Liste adını kontrol edin. Oluşturduktan sonra Word, Excel veya PDF olarak indirebilir; Listelerim\'e kaydedip kontrolü başlatabilirsiniz.',
    'summary.name': 'Liste adı', 'summary.firm': 'İşyeri', 'summary.sector': 'Faaliyet', 'summary.purpose': 'Liste türü', 'summary.freq': 'Sıklık',
    'summary.layout': 'Düzen', 'summary.topics': 'Konular', 'summary.items': 'Sorular', 'summary.edit': 'Düzenle', 'summary.gaps': 'Dikkat',
    'next': 'Devam', 'next.skip': 'Atla', 'next.summary': 'Listeyi oluştur', 'back': 'Geri',
    'result.lists': 'Kaydedilecek listeler', 'result.download': 'Listeyi indir', 'result.word': 'Word', 'result.excel': 'Excel', 'result.pdf': 'PDF',
    'result.save': 'Listelerime kaydet', 'result.saving': 'Kaydediliyor…',
    'result.saveHelp': 'Liste, Kontrol Listeleri › Listelerim bölümüne yayımlanmış olarak eklenir. Katalog soruları doğrulama yöntemi ve açıklamasıyla kopyalanır; sunucu kataloğunda henüz bulunmayan yeni sorular ve sizin eklediğiniz sorular kendi sorunuz olarak kaydedilir.',
    'result.saved': 'Liste Listelerim\'e kaydedildi.', 'result.savedMany': 'liste Listelerim\'e kaydedildi.', 'result.start': 'Kontrolü başlat',
    'result.startHelp': 'Kaydedilen listeyle sahada kontrol başlatın; işyeri ve tarihi sonraki ekranda seçersiniz.',
    'result.method': 'Yöntem', 'result.why': 'Neden listede', 'result.own': 'Sizin sorunuz', 'result.newItem': 'Yeni katalog sorusu',
    'result.note': 'Sihirbaz listesi bir başlangıç taslağıdır; mevzuata uygunluk beyanı değildir. Sorular sahaya göre uzman tarafından gözden geçirilmelidir. Olumsuz yanıt kendiliğinden uygunsuzluk kaydı açmaz.',
    'result.nothing': 'Listede soru yok. Konular adımına dönüp en az bir konu seçin.',
    'save.published': 'Kontrol listesi sihirbazı ile oluşturuldu ve uzman tarafından uygulama üzerinden yayımlandı.',
    'gap.noTopics': 'Konu seçilmedi', 'gap.noFirm': 'İşyeri adı girilmedi (liste adında kullanılır)', 'gap.long': 'Liste uzun; konuları ayrı listelere bölmeyi düşünün',
  };
  const t = k => TEXT[k] || '';
  const vmLabel = vm => (CK && CK.vm[vm] ? CK.vm[vm].l : vm);

  function fresh() { return {purpose: 'site', freq: '', layout: 'single', title: '', off: [], extra: [], itemsOff: [], custom: []}; }

  /* ------------------------------------------------------------ öneri */

  // Bir seçimin özellikleri, katalogdaki çıkarımlar kapanana kadar genişletilmiş hâli.
  function expand(list) {
    const out = new Set(list || []);
    let grew = true;
    while (grew) { grew = false; [...out].forEach(x => (D.fi[x] || []).forEach(y => { if (!out.has(y)) { out.add(y); grew = true; } })); }
    return out;
  }
  /** Bir özelliği hangi seçimin getirdiği (ör. "LPG otogaz", "Kaynak tüpü değiştirme"). */
  function featureReasons(S, f) {
    const out = [];
    const add = x => { if (x && !out.includes(x)) out.push(x); };
    S.sectors.forEach(id => { const s = E.SEC.get(id); if (s && expand(s.f).has(f)) add(s.n); });
    E.activeFollowups(S).forEach(fu => E.answered(S, fu.id).forEach(oid => {
      const o = fu.o.find(x => x.id === oid);
      if (!o || !expand(o.f).has(f)) return;
      const q = fu.q.replace(/\?$/, '');
      add(o.l.length <= 12 ? (q.length > 48 ? q.slice(0, 47) + '…' : q) + ': ' + o.l : o.l);
    }));
    [['equipment', E.EQ], ['tasks', E.TASK], ['materials', E.MAT]].forEach(([k, pool]) => (S[k] || []).forEach(id => {
      const x = pool.get(id); if (x && expand(x.f).has(f)) add(x.n);
    }));
    (S.areas || []).forEach(id => { if (id === f || expand([id]).has(f)) add((E.AREA.get(id) || {}).n); });
    (S.cond || []).forEach(id => { if (id === f || expand([id]).has(f)) add(D.cond[id]); });
    if (/^hazard_class_/.test(f)) add('Tehlike sınıfı: ' + ENG.HC[f.replace('hazard_class_', '')]);
    return out;
  }

  const allowed = (p, purpose) => purpose === 'preuse' ? p.k === 'equipment' : purpose === 'task' ? p.k === 'activity' : true;

  /** Önerilen konular (paketler) ve gerekçeleri; elle eklenenler ve kapatılanlarla birlikte. */
  function topics(S) {
    const F = E.features(S);
    const why = new Map();
    const tag = new Map();
    const add = (id, reason, kindTag) => {
      const p = PACK.get(id);
      if (!p || !allowed(p, C.purpose)) return;
      if (!why.has(id)) why.set(id, []);
      if (reason && !why.get(id).includes(reason)) why.get(id).push(reason);
      if (kindTag && !tag.has(id)) tag.set(id, kindTag);
    };
    if (C.purpose === 'site' && C.freq && CK.freq[C.freq]) add(CK.freq[C.freq], t('topics.freq') + ': ' + t('freq.' + C.freq), 'freq');
    S.sectors.forEach(sid => { const s = E.SEC.get(sid); (CK.sec[sid] || []).forEach(id => add(id, s ? s.n : '', 'sector')); });
    const reasonsOf = new Map();
    CK.packs.forEach(p => {
      const tr = p.tr;
      (tr.eq || []).forEach(id => { if ((S.equipment || []).includes(id)) add(p.id, (E.EQ.get(id) || {}).n); });
      (tr.tk || []).forEach(id => { if ((S.tasks || []).includes(id)) add(p.id, (E.TASK.get(id) || {}).n); });
      (tr.mt || []).forEach(id => { if ((S.materials || []).includes(id)) add(p.id, (E.MAT.get(id) || {}).n); });
      (tr.f || []).forEach(f => {
        if (!F.has(f)) return;
        if (!reasonsOf.has(f)) reasonsOf.set(f, featureReasons(S, f));
        const rs = reasonsOf.get(f);
        if (rs.length) rs.forEach(r => add(p.id, r)); else add(p.id, '');
      });
    });
    if (C.purpose === 'site') CK.core.forEach(id => add(id, t('topics.core'), 'core'));
    const list = [];
    why.forEach((reasons, id) => {
      const p = PACK.get(id);
      list.push({pack: p, suggested: true, core: tag.get(id) === 'core', freq: tag.get(id) === 'freq', sector: tag.get(id) === 'sector',
        why: reasons.length ? reasons : [t('topics.answers')], selected: !C.off.includes(id)});
    });
    C.extra.forEach(id => { if (!why.has(id) && PACK.has(id)) list.push({pack: PACK.get(id), suggested: false, core: false, freq: false, why: [t('topics.manual')], selected: true}); });
    // Genel tur, sonra faaliyetin kendi konuları, sonra türe göre; her işyerindeki konular en sonda.
    const rank = x => x.freq ? -2 : x.sector ? -1 : KIND_ORDER.indexOf(x.pack.k) + (x.core ? 10 : 0);
    list.sort((a, b) => rank(a) - rank(b) || (b.suggested - a.suggested) || (b.why.length - a.why.length) || a.pack.t.localeCompare(b.pack.t, 'tr'));
    return list;
  }

  // Extension packs (nw) point at the extension catalogue; a server without it gets them as the expert's own questions.
  function itemRows(p) {
    return p.it.map(([code, text, vm, db], i) => ({key: p.id + ':' + i, code, text, vm, vmLabel: vmLabel(vm), isNew: !!p.nw,
      ref: db ? {template: p.ref, item: db} : null, selected: !C.itemsOff.includes(p.id + ':' + i)}));
  }

  function defaultTitle(S) {
    const base = C.purpose === 'preuse' ? 'Ekipman kullanım öncesi kontrol listesi' : C.purpose === 'task' ? 'İş öncesi kontrol listesi'
      : (C.freq ? t('freq.' + C.freq) + ' İSG saha kontrol listesi' : 'İSG saha kontrol listesi');
    const firm = (S.firm.name || '').trim();
    return (firm ? firm + ' — ' : '') + base;
  }
  const listTitle = S => (C.title || '').trim() || defaultTitle(S);

  /** Kaydedilecek ve belgeye yazılacak bölümler (yalnız seçili sorular, sizin sorularınızla). İki konuda ortak olan
   *  bir katalog sorusu yalnız ilk konuda yer alır; sunucu aynı soruyu bir listeye iki kez kopyalamaz. */
  function sections(tops) {
    const used = new Set();
    const once = i => !i.code || (used.has(i.code) ? false : (used.add(i.code), true));
    const out = tops.filter(x => x.selected).map(x => ({id: x.pack.id, title: x.pack.t, kind: x.pack.k, kindLabel: t('kind.' + x.pack.k), why: x.why.slice(0, 4),
      sources: x.pack.sr.map(s => CK.src[s] || s),
      items: itemRows(x.pack).filter(i => i.selected && once(i)).map(i => ({code: i.code, text: i.text, vm: i.vm, vmLabel: i.vmLabel, ref: i.ref, isNew: i.isNew, own: false}))
        .concat(C.custom.filter(c => c.pack === x.pack.id && c.text.trim()).map(c => ({code: '', text: c.text.trim(), vm: '', vmLabel: '', ref: null, isNew: false, own: true})))}));
    const loose = C.custom.filter(c => (!c.pack || !out.some(s => s.id === c.pack)) && c.text.trim());
    if (loose.length) out.push({id: 'OWN', title: t('items.own'), kind: 'own', kindLabel: t('items.own'), why: [], sources: [],
      items: loose.map(c => ({code: '', text: c.text.trim(), vm: '', vmLabel: '', ref: null, isNew: false, own: true}))});
    let no = 0;
    out.forEach(s => s.items.forEach(i => { i.no = ++no; }));
    return out.filter(s => s.items.length);
  }

  function gaps(S, secs) {
    const out = [];
    if (!secs.length) out.push(t('gap.noTopics'));
    if (!(S.firm.name || '').trim()) out.push(t('gap.noFirm'));
    if (C.layout === 'single' && secs.reduce((n, s) => n + s.items.length, 0) > 150) out.push(t('gap.long'));
    return out;
  }

  /* ------------------------------------------------------------ görünüm */

  function steps(base) {
    const i = base.indexOf('cond');
    return (i >= 0 ? base.slice(0, i + 1) : base.filter(s => s !== 'summary')).concat(['purpose', 'topics', 'items', 'summary']);
  }

  function checklistView() {
    const S = BASE.state();
    const tops = topics(S);
    const secs = sections(tops);
    return {
      texts: TEXT, version: CK.v, purpose: C.purpose, freq: C.freq, layout: C.layout, title: listTitle(S), titleManual: !!(C.title || '').trim(),
      purposes: PURPOSES.map(id => ({id, title: t('purpose.' + id), help: t('purpose.' + id + '.help'), selected: C.purpose === id})),
      freqs: [''].concat(FREQS).map(id => ({id, title: t(id ? 'freq.' + id : 'freq.none'), selected: C.freq === id})),
      layouts: ['single', 'perTopic'].map(id => ({id, title: t('layout.' + id), selected: C.layout === id})),
      topics: tops.map(x => ({id: x.pack.id, title: x.pack.t, kind: x.pack.k, kindLabel: t('kind.' + x.pack.k), reasons: x.why.slice(0, 3),
        core: x.core, suggested: x.suggested, selected: x.selected, isNew: !!x.pack.nw, questions: x.pack.it.length})),
      groups: tops.filter(x => x.selected).map(x => {
        const rows = itemRows(x.pack);
        return {id: x.pack.id, title: x.pack.t, kindLabel: t('kind.' + x.pack.k), total: rows.length, on: rows.filter(r => r.selected).length,
          items: rows.map(r => ({key: r.key, text: r.text, vm: r.vm, vmLabel: r.vmLabel, isNew: r.isNew, selected: r.selected})),
          custom: C.custom.map((c, index) => ({index, pack: c.pack, text: c.text})).filter(c => c.pack === x.pack.id)};
      }),
      loose: C.custom.map((c, index) => ({index, pack: c.pack, text: c.text})).filter(c => !c.pack || !tops.some(x => x.selected && x.pack.id === c.pack)),
      topicCount: secs.filter(s => s.id !== 'OWN').length, itemCount: secs.reduce((n, s) => n + s.items.length, 0),
      listCount: C.layout === 'perTopic' ? secs.length : (secs.length ? 1 : 0), gaps: gaps(S, secs),
    };
  }

  function decorate(v) {
    v.mode = 'checklist';
    v.steps = steps(v.steps || []);
    v.emergency = null;
    v.checklist = checklistView();
    return v;
  }

  /* ------------------------------------------------------------ eylemler */

  const ACTIONS = {
    ckPurpose(a) { if (PURPOSES.includes(a.id)) C.purpose = a.id; },
    ckFreq(a) { C.freq = FREQS.includes(a.id) ? a.id : ''; },
    ckLayout(a) { if (a.id === 'single' || a.id === 'perTopic') C.layout = a.id; },
    ckTitle(a) { C.title = String(a.value == null ? '' : a.value).slice(0, 180); },
    ckTopic(a) {
      if (!PACK.has(a.id)) return;
      const x = topics(BASE.state()).find(y => y.pack.id === a.id);
      if (x && x.suggested) toggle(C.off, a.id);
      else toggle(C.extra, a.id);
    },
    ckItem(a) { toggle(C.itemsOff, String(a.id)); },
    ckItems(a) {
      const p = PACK.get(a.id);
      if (!p) return;
      const keys = p.it.map((_, i) => p.id + ':' + i);
      const allOn = keys.every(k => !C.itemsOff.includes(k));
      C.itemsOff = allOn ? [...new Set(C.itemsOff.concat(keys))] : C.itemsOff.filter(k => !keys.includes(k));
    },
    ckCustom(a) {
      if (a.op === 'add') {
        const text = String(a.text == null ? '' : a.text).trim().slice(0, 500);
        if (text) C.custom.push({pack: PACK.has(a.pack) ? a.pack : '', text});
      } else if (a.op === 'remove') C.custom.splice(a.index, 1);
      else if (C.custom[a.index]) C.custom[a.index].text = String(a.value == null ? '' : a.value).slice(0, 500);
    },
  };

  /* ------------------------------------------------------------ sonuç */

  function listInput() {
    const S = BASE.state();
    const secs = sections(topics(S));
    const title = listTitle(S);
    const hc = E.hazardClass(S);
    const firm = {name: S.firm.name || '', address: S.firm.address || '', date: S.firm.date || '',
      sector: S.sectors.map(id => E.SEC.get(id).n).join(', '), nace: [...new Set(S.sectors.flatMap(id => E.SEC.get(id).nace))].join(', '),
      hazardClass: hc ? ENG.HC[hc] : ''};
    const flat = s => s.items.map(i => ({text: i.text, section: s.title, ref: i.ref, fallback: !!i.ref && i.isNew, allowsNotApplicable: true}));
    const lists = C.layout === 'perTopic'
      ? secs.map(s => ({title: (title + ' · ' + s.title).slice(0, 190), sections: [s.id], items: flat(s)}))
      : (secs.length ? [{title: title.slice(0, 190), sections: secs.map(s => s.id), items: secs.flatMap(flat)}] : []);
    const items = secs.flatMap(s => s.items);
    return {
      title, firm, purpose: C.purpose, purposeLabel: t('purpose.' + C.purpose), freq: C.freq, freqLabel: C.freq ? t('freq.' + C.freq) : '',
      layout: C.layout, catalog: CK.v, base: CK.base, sections: secs, lists,
      total: items.length, fromCatalog: items.filter(i => i.ref && !i.isNew).length, newCatalog: items.filter(i => i.isNew).length, own: items.filter(i => i.own).length,
      approvalNote: t('save.published'), note: t('result.note'),
      methods: Object.entries(CK.vm).map(([k, v]) => ({id: k, label: v.l, help: v.h})),
    };
  }

  /* ------------------------------------------------------------ belgeler */

  const xmlEsc = s => String(s == null ? '' : s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const blank = v => (v && String(v).trim()) ? v : '……………………………';

  /** Word (.docx), A4 dikey, sahada doldurulacak biçimde. */
  function docx(input) {
    const X = root.RDXlsx;
    const run = (txt, o) => {
      o = o || {};
      const rp = (o.b ? '<w:b/>' : '') + (o.i ? '<w:i/>' : '') + '<w:sz w:val="' + (o.sz || 19) + '"/>' + (o.color ? '<w:color w:val="' + o.color + '"/>' : '');
      return String(txt).split('\n').map((line, i) => (i ? '<w:r><w:br/></w:r>' : '') + '<w:r><w:rPr>' + rp + '</w:rPr><w:t xml:space="preserve">' + xmlEsc(line) + '</w:t></w:r>').join('');
    };
    const p = (txt, o) => { o = o || {}; return '<w:p><w:pPr>' + (o.pageBreak ? '<w:pageBreakBefore/>' : '') + (o.keep ? '<w:keepNext/>' : '') +
      '<w:spacing w:before="' + (o.before || 0) + '" w:after="' + (o.after == null ? 80 : o.after) + '"/></w:pPr>' + run(txt, o) + '</w:p>'; };
    const cell = (txt, w, o) => { o = o || {};
      return '<w:tc><w:tcPr><w:tcW w:w="' + w + '" w:type="dxa"/>' + (o.fill ? '<w:shd w:val="clear" w:color="auto" w:fill="' + o.fill + '"/>' : '') +
        '<w:vAlign w:val="center"/></w:tcPr><w:p><w:pPr><w:spacing w:after="0"/>' + (o.center ? '<w:jc w:val="center"/>' : '') + '</w:pPr>' +
        run(txt, {sz: o.sz || 18, b: o.b, color: o.color}) + '</w:p></w:tc>'; };
    const tr = (cells, header) => '<w:tr><w:trPr><w:cantSplit/>' + (header ? '<w:tblHeader/>' : '') + '</w:trPr>' + cells + '</w:tr>';
    const table = (widths, rows) => '<w:tbl><w:tblPr><w:tblW w:w="' + widths.reduce((a, b) => a + b, 0) + '" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>' +
      ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map(x => '<w:' + x + ' w:val="single" w:sz="4" w:color="B8C2BD"/>').join('') +
      '</w:tblBorders><w:tblCellMar><w:top w:w="50" w:type="dxa"/><w:left w:w="80" w:type="dxa"/><w:bottom w:w="50" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr>' +
      '<w:tblGrid>' + widths.map(w => '<w:gridCol w:w="' + w + '"/>').join('') + '</w:tblGrid>' + rows + '</w:tbl>' + p('', {after: 60});
    const head = (labels, widths) => tr(labels.map((x, i) => cell(x, widths[i], {b: true, fill: '0B2F53', color: 'FFFFFF', center: i > 1 && i < 6, sz: 16})).join(''), true);
    const kv = (rows, w1, w2) => table([w1, w2], rows.map(([k, v]) => tr(cell(k, w1, {b: true, fill: 'EEF2F0'}) + cell(v, w2))).join(''));
    const W = 9900;
    const firm = input.firm || {};
    const WI = [560, 4760, 620, 480, 480, 480, 2520];

    function header(title, pageBreak) {
      let s = p('KONTROL LİSTESİ', {b: true, sz: 17, color: '6B7280', pageBreak, after: 30});
      s += p(title, {b: true, sz: 30, color: '0B2F53', after: 120});
      s += kv([['İşyeri', blank(firm.name)], ['Adres', blank(firm.address)], ['Faaliyet', firm.sector || '—'],
        ['Tehlike sınıfı', firm.hazardClass || '—'], ['Liste türü', input.purposeLabel + (input.freqLabel ? ' · ' + input.freqLabel : '')],
        ['Bölüm / alan', blank('')], ['Ekipman / seri no', blank('')], ['Kontrol tarihi', blank('')], ['Kontrol eden (ad, soyad, unvan)', blank('')]], 3000, W - 3000);
      s += p('U: Uygun · UD: Uygun değil · GD: Gerekli değil (açıklama yazın). Yöntem: ' + input.methods.map(m => m.id + ' ' + m.label.toLocaleLowerCase('tr')).join(', ') + '.', {sz: 16, color: '6B7280'});
      return s;
    }
    function section(s, n) {
      let out = p(n + '. ' + s.title, {b: true, sz: 22, before: 160, after: 40, keep: true});
      if (s.why.length) out += p('Neden listede: ' + s.why.join(', '), {sz: 16, i: true, color: '6B7280', keep: true});
      out += table(WI, head(['No', 'Kontrol sorusu', 'Yöntem', 'U', 'UD', 'GD', 'Açıklama / kanıt'], WI) +
        s.items.map(i => tr(cell(String(i.no), WI[0], {center: true}) + cell(i.text, WI[1]) + cell(i.vm || '—', WI[2], {center: true}) +
          cell('', WI[3]) + cell('', WI[4]) + cell('', WI[5]) + cell('', WI[6]))).join(''));
      return out;
    }
    function closing() {
      const WF = [600, 1000, 4700, 1900, 1700];
      let s = p('Tespit edilen uygunsuzluklar', {b: true, sz: 22, before: 200, after: 60, keep: true});
      s += table(WF, head(['No', 'Soru no', 'Uygunsuzluk ve alınacak önlem', 'Sorumlu', 'Termin'], WF) +
        [1, 2, 3, 4, 5].map(k => tr(cell(String(k), WF[0], {center: true}) + cell('', WF[1]) + cell('\n', WF[2]) + cell('', WF[3]) + cell('', WF[4]))).join(''));
      s += p('Kontrol eden: ……………………………   İmza: ……………   Tarih: ……………', {b: true, before: 240});
      s += p('Sorumlu yönetici: ……………………………   İmza: ……………   Tarih: ……………', {b: true, before: 120});
      return s;
    }

    let body = '';
    const secs = input.sections || [];
    if (input.layout === 'perTopic') {
      secs.forEach((s, i) => { body += header(input.title + ' · ' + s.title, i > 0) + section(s, 1) + closing(); });
    } else {
      body += header(input.title, false);
      secs.forEach((s, i) => { body += section(s, i + 1); });
      body += closing();
    }
    const cited = [...new Set(secs.flatMap(s => s.sources))];
    body += p('Açıklama ve kaynaklar', {b: true, sz: 20, before: 280, after: 60, pageBreak: input.layout === 'perTopic'});
    body += p(input.note, {sz: 16, color: '6B7280'});
    input.methods.forEach(m => { body += p(m.id + ' — ' + m.label + ': ' + m.help, {sz: 16, color: '6B7280', after: 40}); });
    if (cited.length) body += p('Konuların dayandığı kaynaklar: ' + cited.join('; ') + '.', {sz: 16, color: '6B7280'});
    body += p('Katalog: ' + input.catalog + ' (sunucu kataloğu ' + input.base + ') · ' + input.total + ' soru, ' + input.fromCatalog + ' sunucu kataloğundan, ' +
      input.newCatalog + ' yeni katalog sorusu, ' + input.own + ' sizin sorunuz.', {sz: 15, color: '9CA3AF'});

    const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    const field = code => '<w:r><w:rPr><w:sz w:val="16"/><w:color w:val="6B7280"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> ' +
      code + ' </w:instrText></w:r><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>';
    const footer = declaration + '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="center"/></w:pPr>' +
      run('Kontrol listesi' + (firm.name ? ' · ' + firm.name : '') + ' · Sayfa ', {sz: 16, color: '6B7280'}) + field('PAGE') + run(' / ', {sz: 16, color: '6B7280'}) + field('NUMPAGES') + '</w:p></w:ftr>';
    return X.zip({
      '[Content_Types].xml': declaration + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>',
      '_rels/.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/_rels/document.xml.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>',
      'word/styles.xml': declaration + '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="19"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>',
      'word/footer1.xml': footer,
      'word/document.xml': declaration + '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + body +
        '<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="850" w:right="1000" w:bottom="850" w:left="1000" w:header="400" w:footer="400"/></w:sectPr></w:body></w:document>',
    });
  }

  /** Excel (.xlsx): sonuç sütunu açılır listeli, "Uygun değil" kırmızı; kullanıcı metni formül olarak yazılmaz. */
  function xlsx(input) {
    const X = root.RDXlsx;
    const wb = X.workbook({title: 'Kontrol Listesi', creator: 'İSGADA', application: 'İSGADA Kontrol Listesi Sihirbazı'});
    const S = {
      title: wb.style({font: {b: true, sz: 14, color: '0B2F53'}}),
      meta: wb.style({font: {sz: 9, color: '4B5563'}, align: {wrap: true}}),
      head: wb.style({font: {b: true, color: 'FFFFFF'}, fill: '0B2F53', border: true, align: {h: 'center', v: 'center', wrap: true}}),
      section: wb.style({font: {b: true, color: '0B2F53'}, fill: 'E8EEF3', border: true, align: {wrap: true}}),
      cell: wb.style({border: true, align: {wrap: true}, numFmt: '@'}),
      center: wb.style({border: true, align: {h: 'center', wrap: true}}),
      input: wb.style({border: true, fill: 'FFFBEB', align: {wrap: true}, numFmt: '@'}),
      note: wb.style({font: {sz: 9, color: '6B7280'}, align: {wrap: true}}),
    };
    const cols = [5, 60, 8, 16, 34, 18, 12];
    const secs = input.sections || [];
    const lists = input.layout === 'perTopic' ? secs.map(s => ({title: input.title + ' · ' + s.title, secs: [s]})) : [{title: input.title, secs}];
    const firm = input.firm || {};
    const used = new Set();
    lists.forEach((l, li) => {
      let name = (input.layout === 'perTopic' ? (li + 1) + '. ' + l.secs[0].title : 'Kontrol Listesi').replace(/[\\/?*[\]:]/g, ' ').slice(0, 31);
      while (used.has(name)) name = name.slice(0, 28) + ' ' + li;
      used.add(name);
      const sh = wb.sheet(name, {landscape: true, fitWidth: true, freeze: {row: 4, col: 0}, printTitleRows: [4, 4], footer: '&LKontrol listesi&RSayfa &P / &N'});
      sh.cols(cols);
      sh.row([{v: l.title, s: S.title}], {h: 24}); sh.merge(0, 0, 0, cols.length - 1);
      sh.row([{v: ['İşyeri: ' + (firm.name || '—'), firm.address && 'Adres: ' + firm.address, firm.sector && 'Faaliyet: ' + firm.sector,
        firm.hazardClass && 'Tehlike sınıfı: ' + firm.hazardClass, 'Liste türü: ' + input.purposeLabel + (input.freqLabel ? ' · ' + input.freqLabel : '')].filter(Boolean).join(' · '), s: S.meta}], {h: 30});
      sh.merge(1, 0, 1, cols.length - 1);
      sh.row([{v: 'Kontrol tarihi: ………………   Kontrol eden: ………………………   Bölüm / alan: ………………………   Ekipman / seri no: ………………', s: S.meta}]);
      sh.merge(2, 0, 2, cols.length - 1);
      sh.row(['No', 'Kontrol sorusu', 'Yöntem', 'Sonuç', 'Açıklama / kanıt', 'Sorumlu', 'Termin'].map(v => ({v, s: S.head})), {h: 22});
      const first = sh.rowCount;
      l.secs.forEach(s => {
        const r = sh.row([{v: s.title + (s.why.length ? '  ·  ' + s.why.join(', ') : ''), s: S.section}].concat(cols.slice(1).map(() => ({s: S.section}))));
        sh.merge(r, 0, r, cols.length - 1);
        s.items.forEach(i => sh.row([{v: i.no, s: S.center}, {v: i.text, s: S.cell}, {v: i.vm || '—', s: S.center}, {v: null, s: S.input},
          {v: null, s: S.input}, {v: null, s: S.input}, {v: null, s: S.input}]));
      });
      const last = sh.rowCount - 1;
      if (last >= first) {
        sh.listValidation(first, 3, last, 3, ['Uygun', 'Uygun değil', 'Gerekli değil'], {title: 'Sonuç', text: 'Uygun, Uygun değil veya Gerekli değil seçin.'});
        sh.conditional(first, 3, last, 3, [{op: 'equal', f: ['"Uygun değil"'], fill: 'FDECEC', font: {b: true, color: 'B42318'}},
          {op: 'equal', f: ['"Uygun"'], fill: 'E8F5EF', font: {color: '237A3B'}}]);
      }
    });
    const info = wb.sheet('Açıklama', {fitWidth: true, showGrid: false});
    info.cols([18, 90]);
    info.row([{v: 'Açıklama', s: S.title}], {h: 22});
    info.row([{v: 'Sonuç', s: S.head}, {v: 'Uygun · Uygun değil · Gerekli değil (Gerekli değil seçilirse açıklama yazın)', s: S.cell}]);
    input.methods.forEach(m => info.row([{v: m.id + ' — ' + m.label, s: S.cell}, {v: m.help, s: S.cell}]));
    info.row([{v: 'Not', s: S.cell}, {v: input.note, s: S.cell}]);
    const cited = [...new Set(secs.flatMap(s => s.sources))];
    if (cited.length) info.row([{v: 'Kaynaklar', s: S.cell}, {v: cited.join('\n'), s: S.cell}]);
    info.row([{v: 'Katalog', s: S.cell}, {v: input.catalog + ' · sunucu kataloğu ' + input.base + ' · ' + input.total + ' soru', s: S.note}]);
    return wb.bytes();
  }

  /** PDF için metin blokları (yerel çiziciler: title, heading, subheading, text). */
  function blocks(input) {
    const firm = input.firm || {};
    const out = [{type: 'title', text: input.title},
      {type: 'text', text: ['İşyeri: ' + blank(firm.name), firm.address && 'Adres: ' + firm.address, firm.sector && 'Faaliyet: ' + firm.sector,
        firm.hazardClass && 'Tehlike sınıfı: ' + firm.hazardClass, 'Liste türü: ' + input.purposeLabel + (input.freqLabel ? ' · ' + input.freqLabel : ''),
        'Kontrol tarihi: ' + blank(''), 'Kontrol eden: ' + blank(''), 'Bölüm / alan: ' + blank('')].filter(Boolean).join('\n')},
      {type: 'text', text: 'Her soruya U (Uygun), UD (Uygun değil) veya GD (Gerekli değil) işaretleyin. Yöntem: ' +
        input.methods.map(m => m.id + ' ' + m.label.toLocaleLowerCase('tr')).join(', ') + '.'}];
    (input.sections || []).forEach((s, n) => {
      out.push({type: 'heading', text: (n + 1) + '. ' + s.title});
      if (s.why.length) out.push({type: 'text', text: 'Neden listede: ' + s.why.join(', ')});
      out.push({type: 'text', text: s.items.map(i => i.no + '. ' + i.text + (i.vm ? '  [' + i.vm + ']' : '') + '\n     [ ] U    [ ] UD    [ ] GD    Açıklama: ______________________').join('\n')});
    });
    out.push({type: 'heading', text: 'Tespit edilen uygunsuzluklar'});
    out.push({type: 'text', text: [1, 2, 3].map(k => k + '. Soru no: ____  Uygunsuzluk: ____________________  Sorumlu: __________  Termin: ________').join('\n')});
    out.push({type: 'text', text: 'Kontrol eden: ______________________   İmza: __________   Tarih: __________'});
    out.push({type: 'text', text: input.note});
    return out;
  }

  function fileName(ext) {
    const S = BASE.state();
    const safe = (S.firm.name || 'Isyeri').replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_|_$/g, '').slice(0, 60) || 'Isyeri';
    return safe + '_Kontrol_Listesi_' + (S.firm.date || '').replace(/\./g, '-') + '.' + ext;
  }
  const b64 = bytes => {
    const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out = '';
    for (let i = 0; i < bytes.length; i += 3) {
      const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
      out += A[a >> 2] + A[((a & 3) << 4) | ((b || 0) >> 4)] + (i + 1 < bytes.length ? A[((b & 15) << 2) | ((c || 0) >> 6)] : '=') + (i + 2 < bytes.length ? A[c & 63] : '=');
    }
    return out;
  };

  /* ------------------------------------------------------------ köprü */

  const api = Object.assign({}, BASE, {
    init(text, checklistText) {
      D = typeof text === 'string' ? JSON.parse(text) : text;
      const info = BASE.init(D);
      E = ENG.create(D);
      CK = null; PACK = null; on = false;
      if (checklistText) {
        CK = typeof checklistText === 'string' ? JSON.parse(checklistText) : checklistText;
        PACK = new Map(CK.packs.map(p => [p.id, p]));
        info.checklistVersion = CK.v;
        info.checklistPacks = CK.packs.length;
      }
      return info;
    },
    start(opts) {
      opts = opts || {};
      on = opts.mode === 'checklist';
      if (on && !CK) { on = false; throw new Error('Kontrol listesi kataloğu yüklenemedi.'); }
      C = fresh();
      const v = BASE.start(on ? Object.assign({}, opts, {mode: 'risk'}) : opts);
      return on ? decorate(v) : v;
    },
    act(a) {
      if (!on) return BASE.act(a);
      if (a && ACTIONS[a.type]) { ACTIONS[a.type](a); return decorate(BASE.view()); }
      return decorate(BASE.act(a));
    },
    view() { return on ? decorate(BASE.view()) : BASE.view(); },
    result() { return on ? listInput() : BASE.result(); },
    file(format) {
      if (!on) return BASE.file(format);
      const input = listInput();
      const bytes = format === 'xlsx' ? xlsx(input) : docx(input);
      return {name: fileName(format === 'xlsx' ? 'xlsx' : 'docx'), base64: b64(bytes), rows: input.total};
    },
    blocks() { return on ? blocks(listInput()) : BASE.blocks(); },
    fileName(ext, kind) { return on ? fileName(ext) : BASE.fileName(ext, kind); },
    /** Önerilmemiş ve eklenmemiş konular; kısa sorguda tümü (liste türüne uyanlar). */
    topics(q) {
      if (!on) return [];
      q = norm(q);
      const shown = new Set(topics(BASE.state()).map(x => x.pack.id));
      return CK.packs.filter(p => !shown.has(p.id) && allowed(p, C.purpose) && (q.length < 2 || norm(p.t + ' ' + p.al.join(' ')).includes(q)))
        .slice(0, 40).map(p => ({id: p.id, title: p.t, kind: p.k, kindLabel: t('kind.' + p.k), reasons: [], core: false, suggested: false,
          selected: false, isNew: !!p.nw, questions: p.it.length}));
    },
    state() { return on ? {mode: 'checklist', base: BASE.state(), ck: clone(C)} : BASE.state(); },
    restore(state) {
      if (state && state.mode === 'checklist' && CK) { on = true; C = Object.assign(fresh(), clone(state.ck || {})); return decorate(BASE.restore(state.base)); }
      on = false;
      return BASE.restore(state);
    },
  });

  root.RDBridge = api;
  root.RDChecklist = {TEXT, docx, xlsx, blocks};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
