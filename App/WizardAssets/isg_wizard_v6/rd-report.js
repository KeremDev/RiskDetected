/*
 * RDReport — builds the risk assessment workbook (Kapak, Risk Analizi, Önlem Planı, Skala) with RDXlsx.
 * Pure function of its input; the same code serves the web prototype, Node samples and the in-app wizard.
 */
(function (root) {
  'use strict';
  const X = root.RDXlsx || (typeof require !== 'undefined' ? require('./rd-xlsx.js') : null);

  const C = {
    onyx: '0B0D0E', graphite: '1A1D1F', slate: '6B7280', line: 'C9D1CD', fog: 'F1F4F2', cloud: 'F6F7F6', white: 'FFFFFF',
    green: '00B82E', greenDark: '008F24', greenSoft: 'EAF8EE',
  };
  const BANDS = {
    critical: {fill: 'FDDCDC', font: 'B42318'},
    high: {fill: 'FFE4C7', font: 'A35300'},
    medium: {fill: 'FEF3C7', font: '8A6100'},
    low: {fill: 'DDF3E4', font: '1F6B34'},
    insignificant: {fill: 'EEF2F0', font: '4B5563'},
  };
  const FK_LEVELS = [[400, 'Tolerans dışı', 'critical'], [200, 'Yüksek risk', 'high'], [70, 'Önemli risk', 'medium'], [20, 'Olası risk', 'low'], [-1, 'Önemsiz', 'insignificant']];
  const M5_LEVELS = [[19, 'Tolerans dışı', 'critical'], [9, 'Yüksek risk', 'high'], [4, 'Orta risk', 'medium'], [2, 'Düşük risk', 'low'], [-1, 'Önemsiz', 'insignificant']];
  const FK_ACTION = {critical: 'Çalışma derhal durdurulmalı', high: 'Kısa vadede önlem', medium: 'Düzeltici plan gerekli', low: 'Gözetim altında izle', insignificant: 'İzleme yeterli'};
  const M5_ACTION = {critical: 'Çalışma derhal durdurulmalı', high: 'En kısa sürede önlem', medium: 'Plan dahilinde önlem', low: 'Gözetim altında izle', insignificant: 'İzleme yeterli'};

  const level = (levels, r) => levels.find(([min]) => r > min);
  const fkLevel = r => level(FK_LEVELS, r);
  const m5Level = r => level(M5_LEVELS, r);
  const round = v => Math.round(v * 100) / 100;

  /** Report columns. `group` columns expand to several sub-columns. */
  const COLUMNS = [
    {id: 'no', label: 'No', w: 5, required: true},
    {id: 'section', label: 'Bölüm / faaliyet', w: 16},
    {id: 'hazard', label: 'Tehlike', w: 24, required: true},
    {id: 'risk', label: 'Risk (olası olay)', w: 30, required: true},
    {id: 'consequence', label: 'Olası sonuç', w: 20},
    {id: 'affected', label: 'Etkilenenler', w: 16},
    {id: 'existing', label: 'Mevcut durum / önlemler', w: 24},
    {id: 'fk', label: 'Fine-Kinney — mevcut', group: 'fk', method: 'fk'},
    {id: 'm5', label: '5×5 — mevcut', group: 'm5', method: 'm5'},
    {id: 'controls', label: 'Alınacak önlemler', w: 46, required: true},
    {id: 'owner', label: 'Sorumlu', w: 16},
    {id: 'deadline', label: 'Termin', w: 13},
    {id: 'rfk', label: 'Fine-Kinney — önlem sonrası', group: 'fk', method: 'fk', residual: true},
    {id: 'rm5', label: '5×5 — önlem sonrası', group: 'm5', method: 'm5', residual: true},
    {id: 'legal', label: 'İlgili mevzuat', w: 26},
    {id: 'photo', label: 'Fotoğraf', w: 14},
    {id: 'status', label: 'Durum', w: 13},
    {id: 'notes', label: 'Açıklama', w: 18},
  ];
  const SUB = {
    fk: [['P', 'O', 6], ['F', 'F', 6], ['S', 'Ş', 6], ['R', 'R', 8], ['L', 'Seviye', 13]],
    m5: [['L', 'O', 5], ['S', 'Ş', 5], ['R', 'R', 6], ['V', 'Seviye', 12]],
  };

  /** Highest band first; the lowest band uses "between" so blank (zero) cells stay uncoloured. */
  function bandRules(levels) {
    return levels.map(([min, , key], i) => i === levels.length - 1
      ? {op: 'between', f: ['0.01', String(levels[i - 1][0])], fill: BANDS[key].fill, font: {color: BANDS[key].font, b: true}}
      : {op: 'greaterThan', f: [String(min)], fill: BANDS[key].fill, font: {color: BANDS[key].font, b: true}});
  }
  function labelRules(levels) {
    return levels.map(([, label, key]) => ({op: 'equal', f: ['"' + label + '"'], fill: BANDS[key].fill, font: {color: BANDS[key].font, b: true}}));
  }

  function build(input) {
    const firm = input.firm || {};
    const method = input.method || 'both';
    const showFK = method !== 'm5', showM5 = method !== 'fk';
    const chosen = new Set(input.columns || COLUMNS.map(c => c.id));
    const cols = COLUMNS.filter(c => (c.required || chosen.has(c.id)) && (!c.method || (c.method === 'fk' ? showFK : showM5)));
    const rows = input.rows || [];
    const wb = X.workbook({title: 'Risk Değerlendirmesi — ' + (firm.name || ''), creator: input.creator || 'RiskDetected', application: 'RiskDetected'});

    const S = {
      title: wb.style({font: {b: true, sz: 16, color: C.onyx}, align: {v: 'center'}}),
      subtitle: wb.style({font: {sz: 10, color: C.slate}, align: {v: 'center', wrap: true}}),
      overline: wb.style({font: {b: true, sz: 8, color: C.slate}, align: {v: 'center'}}),
      group: wb.style({font: {b: true, sz: 9, color: C.white}, fill: C.onyx, border: {color: '3A3F42'}, align: {h: 'center', v: 'center', wrap: true}}),
      groupAfter: wb.style({font: {b: true, sz: 9, color: C.white}, fill: C.greenDark, border: {color: '3A3F42'}, align: {h: 'center', v: 'center', wrap: true}}),
      head: wb.style({font: {b: true, sz: 9, color: C.graphite}, fill: 'E3E8E5', border: true, align: {h: 'center', v: 'center', wrap: true}}),
      headAfter: wb.style({font: {b: true, sz: 9, color: C.greenDark}, fill: C.greenSoft, border: true, align: {h: 'center', v: 'center', wrap: true}}),
      text: wb.style({font: {sz: 9}, border: true, align: {v: 'top', wrap: true}}),
      textStrong: wb.style({font: {sz: 9, b: true}, border: true, align: {v: 'top', wrap: true}}),
      fill: wb.style({font: {sz: 9, color: C.slate, i: true}, fill: 'FFFBEA', border: true, align: {v: 'top', wrap: true}}),
      num: wb.style({font: {sz: 9}, border: true, align: {h: 'center', v: 'top'}}),
      score: wb.style({font: {sz: 10, b: true}, border: true, align: {h: 'center', v: 'top'}, numFmt: '0.##'}),
      levelCell: wb.style({font: {sz: 9, b: true}, border: true, align: {h: 'center', v: 'top', wrap: true}}),
      label: wb.style({font: {b: true, sz: 10, color: C.graphite}, fill: C.fog, border: true, align: {v: 'center', wrap: true}}),
      value: wb.style({font: {sz: 10}, border: true, align: {v: 'center', wrap: true}}),
      sign: wb.style({font: {sz: 10}, border: true, align: {v: 'center'}}),
    };
    const bandStyle = {}, scoreBand = {}, levelBand = {};
    Object.entries(BANDS).forEach(([k, b]) => {
      bandStyle[k] = wb.style({font: {b: true, sz: 10, color: b.font}, fill: b.fill, border: true, align: {h: 'center', v: 'center', wrap: true}});
      // Static band colours for viewers without conditional formatting; the rules below recolour after edits.
      scoreBand[k] = wb.style({font: {b: true, sz: 10, color: b.font}, fill: b.fill, border: true, align: {h: 'center', v: 'top'}, numFmt: '0.##'});
      levelBand[k] = wb.style({font: {b: true, sz: 9, color: b.font}, fill: b.fill, border: true, align: {h: 'center', v: 'top', wrap: true}});
    });

    // Kapak is created first so it opens first; it is filled after the analysis sheet exists.
    const cover = wb.sheet('Kapak', {fitWidth: true, showGrid: false, tabColor: C.onyx});

    // ---------- Risk Analizi ----------
    const flat = [];
    cols.forEach(c => {
      if (c.group) SUB[c.group].forEach(([key, label, w]) => flat.push({col: c, key, label, w}));
      else flat.push({col: c, key: null, label: c.label, w: c.w});
    });
    const sh = wb.sheet('Risk Analizi', {landscape: true, fitWidth: true, freeze: {row: 4, col: cols.findIndex(c => c.id === 'risk') >= 0 ? flat.findIndex(f => f.col.id === 'risk') : 3},
      printTitleRows: [3, 4], footer: '&L' + (firm.name || '') + '&CRisk Değerlendirmesi&RSayfa &P / &N', tabColor: C.green, zoom: 90});
    sh.cols(flat.map(f => f.w));
    const last = flat.length - 1;
    sh.row([{v: 'RİSK DEĞERLENDİRMESİ' + (firm.name ? ' — ' + firm.name : ''), s: S.title}], {h: 26});
    sh.merge(0, 0, 0, last);
    const methodText = method === 'both' ? 'Fine-Kinney ve 5×5 (L tipi) matris' : method === 'fk' ? 'Fine-Kinney' : '5×5 (L tipi) matris';
    sh.row([{v: [firm.sector && ('Faaliyet: ' + firm.sector), firm.hazardClass && ('Tehlike sınıfı: ' + firm.hazardClass),
      'Yöntem: ' + methodText, firm.date && ('Değerlendirme tarihi: ' + firm.date), firm.validUntil && ('Geçerlilik: ' + firm.validUntil)]
      .filter(Boolean).join('   ·   '), s: S.subtitle}], {h: 18});
    sh.merge(1, 0, 1, last);

    const g = [], h = [];
    flat.forEach((f, i) => {
      const after = !!f.col.residual;
      if (f.col.group) {
        g.push({v: SUB[f.col.group][0][0] === f.key ? f.col.label : null, s: after ? S.groupAfter : S.group});
        h.push({v: f.label, s: after ? S.headAfter : S.head});
      } else {
        g.push({v: f.label, s: S.group});
        h.push({v: null, s: S.group});
      }
    });
    const gRow = sh.row(g, {h: 30});
    sh.row(h, {h: 22});
    let i = 0;
    flat.forEach((f, idx) => {
      if (!f.col.group) sh.merge(gRow, idx, gRow + 1, idx);
    });
    while (i < flat.length) {
      const f = flat[i];
      if (f.col.group) {
        const n = SUB[f.col.group].length;
        sh.merge(gRow, i, gRow, i + n - 1);
        i += n;
      } else i++;
    }

    const firstData = 4;
    const colOf = (id, key) => flat.findIndex(f => f.col.id === id && f.key === key);
    const A = (id, key, r) => X.ref(r, colOf(id, key));
    rows.forEach((row, n) => {
      const r = firstData + n;
      const cells = flat.map(f => {
        const c = f.col;
        if (c.group) {
          const src = row[c.id] || {};
          if (c.group === 'fk') {
            if (f.key === 'P') return {v: src.p, s: S.num};
            if (f.key === 'F') return {v: src.f, s: S.num};
            if (f.key === 'S') return {v: src.s, s: S.num};
            const r0 = round((src.p || 0) * (src.f || 0) * (src.s || 0));
            const lv = fkLevel(r0);
            if (f.key === 'R') return {f: A(c.id, 'P', r) + '*' + A(c.id, 'F', r) + '*' + A(c.id, 'S', r), v: r0, s: scoreBand[lv[2]]};
            const R = A(c.id, 'R', r);
            return {f: 'IF(' + R + '>400,"Tolerans dışı",IF(' + R + '>200,"Yüksek risk",IF(' + R + '>70,"Önemli risk",IF(' + R + '>20,"Olası risk","Önemsiz"))))', v: lv[1], s: levelBand[lv[2]]};
          }
          if (f.key === 'L') return {v: src.l, s: S.num};
          if (f.key === 'S') return {v: src.s, s: S.num};
          const r0 = (src.l || 0) * (src.s || 0);
          const lv = m5Level(r0);
          if (f.key === 'R') return {f: A(c.id, 'L', r) + '*' + A(c.id, 'S', r), v: r0, s: scoreBand[lv[2]]};
          const R = A(c.id, 'R', r);
          return {f: 'IF(' + R + '>19,"Tolerans dışı",IF(' + R + '>9,"Yüksek risk",IF(' + R + '>4,"Orta risk",IF(' + R + '>2,"Düşük risk","Önemsiz"))))', v: lv[1], s: levelBand[lv[2]]};
        }
        switch (c.id) {
          case 'no': return {v: n + 1, s: S.num};
          case 'section': return {v: row.section || '', s: S.text};
          case 'hazard': return {v: row.hazard || '', s: S.textStrong};
          case 'risk': return {v: row.risk || '', s: S.text};
          case 'consequence': return {v: row.consequence || '', s: S.text};
          case 'affected': return {v: row.affected || '', s: S.text};
          case 'existing': return {v: row.existing || '', s: row.existing ? S.text : S.fill};
          case 'controls': return {v: (row.controls || []).map((ct, k) => (k + 1) + '. ' + (input.showHierarchy === false ? '' : '[' + ct.label + '] ') + ct.text).join('\n'), s: S.text};
          case 'owner': return {v: row.owner || '', s: S.text};
          case 'deadline': return {v: row.deadline || '', s: S.text};
          case 'legal': return {v: (row.legal || []).join('\n'), s: S.text};
          case 'photo': return {v: null, s: S.fill};
          case 'status': return {v: row.status || 'Planlandı', s: S.text};
          case 'notes': return {v: row.notes || '', s: S.text};
          default: return {v: '', s: S.text};
        }
      });
      sh.row(cells);
    });
    const lastRow = firstData + Math.max(rows.length, 1) - 1;
    const rangeRows = Math.max(lastRow, firstData + 200);
    if (rows.length) sh.filter(gRow + 1, 0, lastRow, last);
    ['fk', 'rfk'].forEach(id => {
      if (colOf(id, 'R') < 0) return;
      const rc = colOf(id, 'R'), lc = colOf(id, 'L');
      sh.conditional(firstData, rc, rangeRows, rc, bandRules(FK_LEVELS));
      sh.conditional(firstData, lc, rangeRows, lc, labelRules(FK_LEVELS));
      sh.listValidation(firstData, colOf(id, 'P'), rangeRows, colOf(id, 'P'), ['0.2', '0.5', '1', '3', '6', '10'], {title: 'Olasılık', text: '0.2 / 0.5 / 1 / 3 / 6 / 10'});
      sh.listValidation(firstData, colOf(id, 'F'), rangeRows, colOf(id, 'F'), ['0.5', '1', '2', '3', '6', '10'], {title: 'Frekans', text: '0.5 / 1 / 2 / 3 / 6 / 10'});
      sh.listValidation(firstData, colOf(id, 'S'), rangeRows, colOf(id, 'S'), ['1', '3', '7', '15', '40', '100'], {title: 'Şiddet', text: '1 / 3 / 7 / 15 / 40 / 100'});
    });
    ['m5', 'rm5'].forEach(id => {
      if (colOf(id, 'R') < 0) return;
      const rc = colOf(id, 'R'), vc = colOf(id, 'V');
      sh.conditional(firstData, rc, rangeRows, rc, bandRules(M5_LEVELS));
      sh.conditional(firstData, vc, rangeRows, vc, labelRules(M5_LEVELS));
      sh.listValidation(firstData, colOf(id, 'L'), rangeRows, colOf(id, 'L'), ['1', '2', '3', '4', '5'], {title: 'Olasılık', text: '1–5'});
      sh.listValidation(firstData, colOf(id, 'S'), rangeRows, colOf(id, 'S'), ['1', '2', '3', '4', '5'], {title: 'Şiddet', text: '1–5'});
    });
    if (colOf('status', null) >= 0) {
      const c = colOf('status', null);
      sh.listValidation(firstData, c, rangeRows, c, ['Planlandı', 'Devam ediyor', 'Tamamlandı', 'Ertelendi'], {title: 'Durum', text: 'Listeden seçin'});
    }

    // ---------- Kapak ----------
    cover.cols([30, 28, 22, 22, 22, 22]);
    cover.row([{v: 'RİSK DEĞERLENDİRMESİ', s: S.title}], {h: 30});
    cover.merge(0, 0, 0, 5);
    cover.row([{v: 'Bu belge RiskDetected risk analizi sihirbazıyla hazırlanan taslaktır; skorlar tipik saha koşuluna göre önerilmiştir ve değerlendirme ekibince sahada doğrulanmalıdır.', s: S.subtitle}], {h: 30});
    cover.merge(1, 0, 1, 5);
    cover.row([]);
    const info = [['Firma / işyeri', firm.name], ['Adres', firm.address], ['Faaliyet', firm.sector], ['NACE', firm.nace],
      ['Tehlike sınıfı', firm.hazardClass], ['Çalışan sayısı', firm.employees], ['Değerlendirme tarihi', firm.date],
      ['Geçerlilik (yenileme) tarihi', firm.validUntil], ['Yöntem', methodText]];
    info.forEach(([k, v]) => {
      const r = cover.row([{v: k, s: S.label}, {v: v || '', s: v ? S.value : S.fill}]);
      cover.merge(r, 1, r, 5);
    });
    cover.row([]);
    cover.row([{v: 'DEĞERLENDİRME EKİBİ', s: S.overline}]);
    cover.row(['Görev', 'Adı soyadı', 'Unvan / belge', 'İmza', '', ''].map((v, k) => ({v: k < 4 ? v : null, s: S.head})));
    const teamRow = cover.rowCount - 1;
    cover.merge(teamRow, 3, teamRow, 5);
    (input.team || ['İşveren / işveren vekili', 'İş güvenliği uzmanı', 'İşyeri hekimi', 'Çalışan temsilcisi', 'Destek elemanı', 'Bilgi sahibi çalışan'])
      .forEach(role => {
        const r = cover.row([{v: role, s: S.label}, {v: null, s: S.sign}, {v: null, s: S.sign}, {v: null, s: S.sign}, {v: null, s: S.sign}, {v: null, s: S.sign}], {h: 26});
        cover.merge(r, 3, r, 5);
      });
    cover.row([]);
    cover.row([{v: 'RİSK DAĞILIMI', s: S.overline}]);
    const sheetRef = "'Risk Analizi'!";
    const summaryCols = [];
    if (showFK) summaryCols.push(['FK mevcut', 'fk', FK_LEVELS], ['FK önlem sonrası', 'rfk', FK_LEVELS]);
    if (showM5) summaryCols.push(['5×5 mevcut', 'm5', M5_LEVELS], ['5×5 önlem sonrası', 'rm5', M5_LEVELS]);
    cover.row([{v: 'Seviye', s: S.head}].concat(summaryCols.map(([t]) => ({v: t, s: S.head}))));
    const levelNames = [['Tolerans dışı', 'critical'], ['Yüksek risk', 'high'], ['Önemli / orta risk', 'medium'], ['Olası / düşük risk', 'low'], ['Önemsiz', 'insignificant']];
    levelNames.forEach(([name, key], li) => {
      cover.row([{v: name, s: bandStyle[key]}].concat(summaryCols.map(([, id, levels]) => {
        const lc = colOf(id, id.indexOf('m5') >= 0 ? 'V' : 'L');
        if (lc < 0) return {v: 0, s: S.num};
        const label = levels[li][1];
        const count = rows.filter(row => {
          const src = row[id] || {};
          const r0 = id.indexOf('m5') >= 0 ? (src.l || 0) * (src.s || 0) : (src.p || 0) * (src.f || 0) * (src.s || 0);
          return (id.indexOf('m5') >= 0 ? m5Level(r0) : fkLevel(r0))[1] === label;
        }).length;
        const col = X.colName(lc);
        return {f: 'COUNTIF(' + sheetRef + '$' + col + '$' + (firstData + 1) + ':$' + col + '$' + (rangeRows + 1) + ',"' + label + '")', v: count, s: S.num};
      })));
    });
    cover.row([{v: 'Toplam', s: S.label}].concat(summaryCols.map(() => ({v: rows.length, s: S.num}))));

    // ---------- Önlem Planı ----------
    const plan = wb.sheet('Önlem Planı', {landscape: true, fitWidth: true, freeze: {row: 1, col: 0}, printTitleRows: [1, 1], tabColor: C.greenDark});
    plan.cols([6, 12, 34, 50, 16, 18, 14, 14, 14, 18]);
    plan.row(['Risk no', 'Öncelik', 'Tehlike / risk', 'Alınacak önlem', 'Hiyerarşi', 'Sorumlu', 'Termin', 'Durum', 'Tamamlanma', 'Kontrol eden'].map(v => ({v, s: S.group})), {h: 26});
    const planned = rows.map((row, n) => ({row, n, r0: fkScore(row.fk)})).sort((a, b) => b.r0 - a.r0);
    planned.forEach(({row, n}) => {
      const lv = showFK ? fkLevel(fkScore(row.fk)) : m5Level(m5Score(row.m5));
      (row.controls || []).forEach(ct => {
        plan.row([{v: n + 1, s: S.num}, {v: lv[1], s: bandStyle[lv[2]]}, {v: row.hazard + '\n' + row.risk, s: S.text}, {v: ct.text, s: S.text},
          {v: ct.label, s: S.text}, {v: ct.owner || row.owner || '', s: S.text}, {v: row.deadline || '', s: S.text}, {v: 'Planlandı', s: S.text},
          {v: null, s: S.fill}, {v: null, s: S.fill}]);
      });
    });
    if (plan.rowCount > 1) {
      plan.listValidation(1, 7, plan.rowCount - 1, 7, ['Planlandı', 'Devam ediyor', 'Tamamlandı', 'Ertelendi'], {title: 'Durum', text: 'Listeden seçin'});
      plan.filter(0, 0, plan.rowCount - 1, 9);
    }

    // ---------- Skala ----------
    const scale = wb.sheet('Skala ve Açıklama', {fitWidth: true, showGrid: false, tabColor: C.slate});
    scale.cols([16, 44, 4, 16, 12, 12, 12, 12, 12]);
    scale.row([{v: 'FINE-KINNEY  ·  R = O × F × Ş', s: S.overline}]);
    const fkTables = [
      ['Olasılık (O)', [[0.2, 'Neredeyse imkânsız'], [0.5, 'Zayıf ihtimal'], [1, 'Oldukça düşük ihtimal'], [3, 'Nadir fakat olabilir'], [6, 'Kuvvetle muhtemel'], [10, 'Çok kuvvetli ihtimal / beklenir']]],
      ['Frekans (F)', [[0.5, 'Çok nadir (yılda bir veya daha az)'], [1, 'Oldukça nadir (yılda birkaç kez)'], [2, 'Nadir (ayda bir)'], [3, 'Ara sıra (haftada bir)'], [6, 'Sık (günde bir veya birkaç kez)'], [10, 'Sürekli']]],
      ['Şiddet (Ş)', [[1, 'Çok hafif — ilkyardım gerektirmeyen'], [3, 'Hafif — ilkyardım / ayakta tedavi'], [7, 'Orta — iş günü kaybı'], [15, 'Ciddi — uzuv kaybı, kalıcı hasar'], [40, 'Çok ciddi — ölüm, sürekli iş göremezlik'], [100, 'Felaket — birden çok ölüm']]],
    ];
    fkTables.forEach(([title, items]) => {
      scale.row([{v: title, s: S.head}, {v: 'Açıklama', s: S.head}]);
      items.forEach(([v, t]) => scale.row([{v, s: S.num}, {v: t, s: S.text}]));
      scale.row([]);
    });
    scale.row([{v: 'Risk skoru', s: S.head}, {v: 'Seviye ve yapılacak iş', s: S.head}]);
    [['R > 400', 'critical', 'Tolerans dışı — ' + FK_ACTION.critical], ['200 < R ≤ 400', 'high', 'Yüksek risk — ' + FK_ACTION.high],
      ['70 < R ≤ 200', 'medium', 'Önemli risk — ' + FK_ACTION.medium], ['20 < R ≤ 70', 'low', 'Olası risk — ' + FK_ACTION.low],
      ['R ≤ 20', 'insignificant', 'Önemsiz — ' + FK_ACTION.insignificant]].forEach(([r, key, t]) => scale.row([{v: r, s: bandStyle[key]}, {v: t, s: S.text}]));
    scale.row([]);
    scale.row([{v: '5×5 L TİPİ MATRİS  ·  R = O × Ş', s: S.overline}]);
    scale.row([{v: 'Olasılık ↓ / Şiddet →', s: S.head}, {v: 'Açıklama', s: S.head}, {v: null}, {v: 'O \\ Ş', s: S.head}].concat([1, 2, 3, 4, 5].map(s => ({v: s, s: S.head}))));
    const m5P = ['Çok küçük (hemen hemen hiç)', 'Küçük (çok az)', 'Orta (az)', 'Yüksek (sıklıkla)', 'Çok yüksek (hemen hemen her zaman)'];
    [5, 4, 3, 2, 1].forEach(l => {
      scale.row([{v: l, s: S.num}, {v: m5P[l - 1], s: S.text}, {v: null}, {v: l, s: S.head}].concat([1, 2, 3, 4, 5].map(s => ({v: l * s, s: bandStyle[m5Level(l * s)[2]]}))));
    });
    scale.row([]);
    [['R ≥ 20', 'critical', 'Tolerans dışı — ' + M5_ACTION.critical], ['10–19', 'high', 'Yüksek risk — ' + M5_ACTION.high], ['5–9', 'medium', 'Orta risk — ' + M5_ACTION.medium],
      ['3–4', 'low', 'Düşük risk — ' + M5_ACTION.low], ['1–2', 'insignificant', 'Önemsiz — ' + M5_ACTION.insignificant]].forEach(([r, key, t]) => scale.row([{v: r, s: bandStyle[key]}, {v: t, s: S.text}]));
    scale.row([]);
    scale.row([{v: 'Not', s: S.head}, {v: 'Önerilen skorlar; 5×5 olasılığı Fine-Kinney O × F çarpımından türetilir (≤5 → 1, ≤12 → 2, ≤18 → 3, ≤30 → 4, >30 → 5). Şiddet sınıfı iki yöntemde eşleştirilir (FK 1/3/7/15/40/100 ↔ 5×5 1/2/3/4/5/5). Değerlendirme ekibi her satırı sahadaki gerçek duruma göre düzenlemelidir.', s: S.text}], {h: 64});

    return wb.bytes();
  }

  const xmlEsc = s => String(s == null ? '' : s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const methodLabel = m => m === 'both' ? 'Fine-Kinney ve 5×5 (L tipi) matris' : m === 'fk' ? 'Fine-Kinney' : '5×5 (L tipi) matris';
  const scoreText = (v, kind) => kind === 'fk'
    ? 'O ' + v.p + ' × F ' + v.f + ' × Ş ' + v.s + ' = ' + Math.round(fkScore(v) * 100) / 100 + '\n' + fkLevel(fkScore(v))[1]
    : 'O ' + v.l + ' × Ş ' + v.s + ' = ' + m5Score(v) + '\n' + m5Level(m5Score(v))[1];

  /** Word (.docx): kapak bilgileri, ekip tablosu ve renkli risk tablosu; A4 yatay. */
  function docx(input) {
    const firm = input.firm || {};
    const rows = input.rows || [];
    const showFK = input.method !== 'm5', showM5 = input.method !== 'fk';
    const run = (t, o) => {
      o = o || {};
      const rp = (o.b ? '<w:b/>' : '') + '<w:sz w:val="' + (o.sz || 16) + '"/>' + (o.color ? '<w:color w:val="' + o.color + '"/>' : '');
      return String(t).split('\n').map((line, i) => (i ? '<w:r><w:br/></w:r>' : '') + '<w:r><w:rPr>' + rp + '</w:rPr><w:t xml:space="preserve">' + xmlEsc(line) + '</w:t></w:r>').join('');
    };
    const p = (t, o) => '<w:p><w:pPr><w:spacing w:after="' + ((o && o.after) || 60) + '"/></w:pPr>' + run(t, o) + '</w:p>';
    const cell = (t, w, o) => {
      o = o || {};
      return '<w:tc><w:tcPr><w:tcW w:w="' + w + '" w:type="dxa"/>' + (o.fill ? '<w:shd w:val="clear" w:color="auto" w:fill="' + o.fill + '"/>' : '') +
        '</w:tcPr><w:p><w:pPr><w:spacing w:after="0"/>' + (o.center ? '<w:jc w:val="center"/>' : '') + '</w:pPr>' + run(t, {sz: o.sz || 14, b: o.b, color: o.color}) + '</w:p></w:tc>';
    };
    const table = (widths, body) => '<w:tbl><w:tblPr><w:tblW w:w="' + widths.reduce((a, b) => a + b, 0) + '" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>' +
      ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map(x => '<w:' + x + ' w:val="single" w:sz="4" w:color="C9D1CD"/>').join('') +
      '</w:tblBorders><w:tblCellMar><w:top w:w="50" w:type="dxa"/><w:left w:w="70" w:type="dxa"/><w:bottom w:w="50" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr>' +
      '<w:tblGrid>' + widths.map(w => '<w:gridCol w:w="' + w + '"/>').join('') + '</w:tblGrid>' + body + '</w:tbl>';
    const tr = (cells, header) => '<w:tr><w:trPr><w:cantSplit/>' + (header ? '<w:tblHeader/>' : '') + '</w:trPr>' + cells + '</w:tr>';

    let body = p('RİSK DEĞERLENDİRMESİ' + (firm.name ? ' — ' + firm.name : ''), {b: true, sz: 30, after: 120});
    body += p([firm.sector && 'Faaliyet: ' + firm.sector, firm.nace && 'NACE: ' + firm.nace, firm.hazardClass && 'Tehlike sınıfı: ' + firm.hazardClass,
      firm.employees && 'Çalışan sayısı: ' + firm.employees].filter(Boolean).join('   ·   '), {sz: 18, color: '6B7280'});
    body += p([firm.date && 'Değerlendirme tarihi: ' + firm.date, firm.validUntil && 'Geçerlilik: ' + firm.validUntil, 'Yöntem: ' + methodLabel(input.method)]
      .filter(Boolean).join('   ·   '), {sz: 18, color: '6B7280', after: 160});
    body += p('Değerlendirme ekibi', {b: true, sz: 20});
    body += table([4200, 4200, 3200, 3200], tr(['Görev', 'Adı soyadı', 'Unvan / belge', 'İmza'].map((t, i) => cell(t, [4200, 4200, 3200, 3200][i], {b: true, fill: 'E3E8E5'})).join(''), true) +
      ['İşveren / işveren vekili', 'İş güvenliği uzmanı', 'İşyeri hekimi', 'Çalışan temsilcisi', 'Destek elemanı', 'Bilgi sahibi çalışan']
        .map(role => tr(cell(role, 4200, {sz: 16}) + cell('', 4200) + cell('', 3200) + cell('', 3200))).join(''));
    body += p('', {after: 160});
    const head = ['No', 'Tehlike / risk', 'Olası sonuç'];
    const widths = [500, 3000, 1700];
    if (showFK) { head.push('FK mevcut'); widths.push(1350); }
    if (showM5) { head.push('5×5 mevcut'); widths.push(1150); }
    head.push('Alınacak önlemler', 'Sorumlu / termin');
    widths.push(showFK && showM5 ? 4300 : 5450, 1500);
    if (showFK) { head.push('FK sonrası'); widths.push(1350); }
    if (showM5) { head.push('5×5 sonrası'); widths.push(1150); }
    let tbody = tr(head.map((t, i) => cell(t, widths[i], {b: true, fill: '0B0D0E', color: 'FFFFFF', sz: 14})).join(''), true);
    let section = null;
    rows.forEach((r, n) => {
      if (r.section !== section) {
        section = r.section;
        tbody += '<w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr><w:tcW w:w="' + widths.reduce((a, b) => a + b, 0) + '" w:type="dxa"/><w:gridSpan w:val="' + widths.length +
          '"/><w:shd w:val="clear" w:color="auto" w:fill="F1F4F2"/></w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr>' + run(section, {b: true, sz: 16}) + '</w:p></w:tc></w:tr>';
      }
      const band = (lv) => BANDS[lv[2]];
      const scoreCell = (v, kind, w) => {
        const lv = kind === 'fk' ? fkLevel(fkScore(v)) : m5Level(m5Score(v));
        return cell(scoreText(v, kind), w, {fill: band(lv).fill, color: band(lv).font, b: true, center: true, sz: 13});
      };
      let cells = cell(String(n + 1), widths[0], {center: true}) + cell(r.hazard + '\n' + r.risk, widths[1]) + cell(r.consequence, widths[2]);
      let i = 3;
      if (showFK) cells += scoreCell(r.fk, 'fk', widths[i++]);
      if (showM5) cells += scoreCell(r.m5, 'm5', widths[i++]);
      cells += cell((r.controls || []).map((c, k) => (k + 1) + '. [' + c.label + '] ' + c.text).join('\n'), widths[i++]);
      cells += cell([r.owner, r.deadline].filter(Boolean).join('\n'), widths[i++]);
      if (showFK) cells += scoreCell(r.rfk, 'fk', widths[i++]);
      if (showM5) cells += scoreCell(r.rm5, 'm5', widths[i++]);
      tbody += tr(cells);
    });
    body += table(widths, tbody);
    body += p('', {after: 80});
    body += p('Skorlar RiskDetected kataloğunun tipik saha koşuluna göre önerdiği değerlerdir; değerlendirme ekibi sahada doğrulamalıdır. ' +
      '5×5 olasılığı Fine-Kinney O × F çarpımından türetilir.', {sz: 14, color: '6B7280'});
    const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    const files = {
      '[Content_Types].xml': declaration + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
      '_rels/.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/_rels/document.xml.rels': declaration + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'word/styles.xml': declaration + '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="18"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>',
      'word/document.xml': declaration + '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + body +
        '<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/><w:pgMar w:top="720" w:right="600" w:bottom="720" w:left="600" w:header="400" w:footer="400"/></w:sectPr></w:body></w:document>',
    };
    return X.zip(files);
  }

  /** PDF için sade metin blokları (yerel PDF çiziciler kullanır). */
  function blocks(input) {
    const firm = input.firm || {};
    const out = [{type: 'title', text: 'Risk Değerlendirmesi' + (firm.name ? ' — ' + firm.name : '')},
      {type: 'text', text: [firm.sector && 'Faaliyet: ' + firm.sector, firm.hazardClass && 'Tehlike sınıfı: ' + firm.hazardClass,
        firm.date && 'Tarih: ' + firm.date, firm.validUntil && 'Geçerlilik: ' + firm.validUntil, 'Yöntem: ' + methodLabel(input.method)].filter(Boolean).join(' · ')}];
    let section = null;
    (input.rows || []).forEach((r, n) => {
      if (r.section !== section) { section = r.section; out.push({type: 'heading', text: section}); }
      const fk = fkLevel(fkScore(r.fk)), rfk = fkLevel(fkScore(r.rfk)), m5 = m5Level(m5Score(r.m5)), rm5 = m5Level(m5Score(r.rm5));
      const scores = [input.method !== 'm5' && 'FK ' + Math.round(fkScore(r.fk) * 100) / 100 + ' ' + fk[1] + ' → ' + Math.round(fkScore(r.rfk) * 100) / 100 + ' ' + rfk[1],
        input.method !== 'fk' && '5×5 ' + m5Score(r.m5) + ' ' + m5[1] + ' → ' + m5Score(r.rm5) + ' ' + rm5[1]].filter(Boolean).join(' · ');
      out.push({type: 'subheading', text: (n + 1) + '. ' + r.hazard});
      out.push({type: 'text', text: r.risk + '\nOlası sonuç: ' + r.consequence + (r.affected ? ' · Etkilenenler: ' + r.affected : '') + '\n' + scores +
        '\n' + (r.controls || []).map(c => '• [' + c.label + '] ' + c.text).join('\n') + (r.owner ? '\nSorumlu: ' + r.owner : '') + (r.legal && r.legal.length ? '\nMevzuat: ' + r.legal.join('; ') : '')});
    });
    out.push({type: 'text', text: 'Skorlar katalog önerisidir; değerlendirme ekibi sahada doğrulamalıdır.'});
    return out;
  }

  function fkScore(v) { v = v || {}; return (v.p || 0) * (v.f || 0) * (v.s || 0); }
  function m5Score(v) { v = v || {}; return (v.l || 0) * (v.s || 0); }

  root.RDReport = {build, docx, blocks, COLUMNS, FK_LEVELS, M5_LEVELS, FK_ACTION, M5_ACTION, BANDS, fkLevel, m5Level, fkScore, m5Score};
  if (typeof module !== 'undefined' && module.exports) module.exports = root.RDReport;
})(typeof globalThis !== 'undefined' ? globalThis : this);
