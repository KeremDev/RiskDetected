/*
 * RDXlsx — dependency-free, styled OOXML (.xlsx) writer.
 *
 * Runs unchanged in browsers, Node and JavaScriptCore / Android WebView (no DOM, no network, no eval).
 * Supports: several sheets, fonts, solid fills, thin borders, alignment, number formats, formulas with
 * cached values, merged cells, frozen panes, auto filter, list validation, conditional formatting,
 * landscape fit-to-width printing and repeated print titles.
 *
 *   const wb = RDXlsx.workbook({title: 'Risk Değerlendirmesi', creator: 'ISGADA'});
 *   const head = wb.style({font: {b: true, color: 'FFFFFF'}, fill: '0B0D0E', border: true, align: {h: 'center', wrap: true}});
 *   const sh = wb.sheet('Risk Analizi', {landscape: true, fitWidth: true, freeze: {row: 1, col: 2}});
 *   sh.cols([6, 30, 40]);
 *   sh.row(['No', 'Tehlike', 'Risk'].map(v => ({v, s: head})));
 *   sh.row([{v: 1}, {v: 'Islak zemin'}, {f: 'A2*2', v: 2}]);
 *   const bytes = wb.bytes();   // Uint8Array
 */
(function (root) {
  'use strict';

  const XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  const NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const NS_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const NS_PKG_REL = 'http://schemas.openxmlformats.org/package/2006/relationships';

  const esc = s => String(s == null ? '' : s)
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  function utf8(str) {
    if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(str);
    const out = [];
    for (let i = 0; i < str.length; i++) {
      let c = str.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        c = 0x10000 + ((c - 0xd800) << 10) + (str.charCodeAt(++i) - 0xdc00);
      }
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | c >> 6, 0x80 | c & 63);
      else if (c < 0x10000) out.push(0xe0 | c >> 12, 0x80 | c >> 6 & 63, 0x80 | c & 63);
      else out.push(0xf0 | c >> 18, 0x80 | c >> 12 & 63, 0x80 | c >> 6 & 63, 0x80 | c & 63);
    }
    return new Uint8Array(out);
  }

  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 255] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  /** Stored (uncompressed) ZIP with UTF-8 names; deterministic order and timestamp. */
  function zip(files) {
    const parts = [];
    const central = [];
    let offset = 0;
    const u16 = v => [v & 255, v >> 8 & 255];
    const u32 = v => [v & 255, v >> 8 & 255, v >> 16 & 255, v >>> 24 & 255];
    const DOS_TIME = 0, DOS_DATE = (2026 - 1980) << 9 | 1 << 5 | 1;
    for (const name of Object.keys(files)) {
      const nameBytes = utf8(name);
      const data = typeof files[name] === 'string' ? utf8(files[name]) : files[name];
      const crc = crc32(data);
      const local = new Uint8Array([
        ...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(DOS_TIME), ...u16(DOS_DATE),
        ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(nameBytes.length), ...u16(0), ...nameBytes]);
      parts.push(local, data);
      central.push(new Uint8Array([
        ...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(DOS_TIME), ...u16(DOS_DATE),
        ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(nameBytes.length), ...u16(0), ...u16(0),
        ...u16(0), ...u16(0), ...u32(0), ...u32(offset), ...nameBytes]));
      offset += local.length + data.length;
    }
    const centralSize = central.reduce((n, c) => n + c.length, 0);
    const end = new Uint8Array([
      ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(central.length), ...u16(central.length),
      ...u32(centralSize), ...u32(offset), ...u16(0)]);
    const all = parts.concat(central, [end]);
    const out = new Uint8Array(all.reduce((n, p) => n + p.length, 0));
    let at = 0;
    for (const p of all) { out.set(p, at); at += p.length; }
    return out;
  }

  function colName(index) { // 0 → A
    let n = index + 1, s = '';
    while (n) { s = String.fromCharCode(65 + (n - 1) % 26) + s; n = Math.floor((n - 1) / 26); }
    return s;
  }

  const ref = (row, col) => colName(col) + (row + 1);

  function workbook(meta) {
    meta = meta || {};
    const fonts = ['<font><sz val="10"/><color rgb="FF1A1D1F"/><name val="Calibri"/><family val="2"/></font>'];
    const fills = ['<fill><patternFill patternType="none"/></fill>', '<fill><patternFill patternType="gray125"/></fill>'];
    const borders = ['<border><left/><right/><top/><bottom/><diagonal/></border>'];
    const numFmts = [];
    const xfs = ['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'];
    const dxfs = [];
    const styleCache = new Map();
    const sheets = [];

    const argb = hex => 'FF' + String(hex).replace('#', '').toUpperCase();

    function fontXml(f) {
      return '<font>' + (f.b ? '<b/>' : '') + (f.i ? '<i/>' : '') + '<sz val="' + (f.sz || 10) + '"/>' +
        '<color rgb="' + argb(f.color || '1A1D1F') + '"/><name val="' + esc(f.name || 'Calibri') + '"/><family val="2"/></font>';
    }
    const fillXml = hex => '<fill><patternFill patternType="solid"><fgColor rgb="' + argb(hex) + '"/><bgColor indexed="64"/></patternFill></fill>';
    function borderXml(b) {
      const color = argb(b.color || 'C9D1CD');
      const side = n => '<' + n + ' style="' + (b.style || 'thin') + '"><color rgb="' + color + '"/></' + n + '>';
      return '<border>' + side('left') + side('right') + side('top') + side('bottom') + '<diagonal/></border>';
    }
    function indexOf(list, xml) {
      const i = list.indexOf(xml);
      if (i >= 0) return i;
      list.push(xml);
      return list.length - 1;
    }

    /** Returns a style id for {font, fill, border, align:{h,v,wrap,indent,rotate}, numFmt}. */
    function style(spec) {
      const key = JSON.stringify(spec || {});
      if (styleCache.has(key)) return styleCache.get(key);
      spec = spec || {};
      const fontId = spec.font ? indexOf(fonts, fontXml(spec.font)) : 0;
      const fillId = spec.fill ? indexOf(fills, fillXml(spec.fill)) : 0;
      const borderId = spec.border ? indexOf(borders, borderXml(spec.border === true ? {} : spec.border)) : 0;
      let numFmtId = 0;
      if (spec.numFmt) {
        const builtin = {'0': 1, '0.00': 2, '@': 49, 'dd.mm.yyyy': null}[spec.numFmt];
        if (builtin) numFmtId = builtin;
        else {
          const existing = numFmts.find(n => n.code === spec.numFmt);
          numFmtId = existing ? existing.id : 164 + numFmts.length;
          if (!existing) numFmts.push({id: numFmtId, code: spec.numFmt});
        }
      }
      const a = spec.align || {};
      const align = (a.h || a.v || a.wrap || a.indent || a.rotate)
        ? '<alignment' + (a.h ? ' horizontal="' + a.h + '"' : '') + ' vertical="' + (a.v || 'top') + '"' +
          (a.wrap ? ' wrapText="1"' : '') + (a.indent ? ' indent="' + a.indent + '"' : '') +
          (a.rotate ? ' textRotation="' + a.rotate + '"' : '') + '/>'
        : '<alignment vertical="top"/>';
      const xf = '<xf numFmtId="' + numFmtId + '" fontId="' + fontId + '" fillId="' + fillId + '" borderId="' + borderId +
        '" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"' + (numFmtId ? ' applyNumberFormat="1"' : '') +
        '>' + align + '</xf>';
      const id = indexOf(xfs, xf);
      styleCache.set(key, id);
      return id;
    }

    /** Differential format for conditional formatting: {font, fill}. */
    function dxf(spec) {
      const xml = '<dxf>' + (spec.font ? '<font>' + (spec.font.b ? '<b/>' : '') + '<color rgb="' + argb(spec.font.color || '1A1D1F') + '"/></font>' : '') +
        (spec.fill ? '<fill><patternFill patternType="solid"><fgColor rgb="' + argb(spec.fill) + '"/><bgColor rgb="' + argb(spec.fill) + '"/></patternFill></fill>' : '') + '</dxf>';
      return indexOf(dxfs, xml);
    }

    function sheet(name, opts) {
      opts = opts || {};
      const sh = {
        name: String(name).replace(/[\\/?*[\]:]/g, ' ').slice(0, 31), opts, rows: [], widths: [], merges: [],
        validations: [], conditions: [], heights: {}, filter: null,
      };
      const api = {
        cols(widths) { sh.widths = widths.slice(); return api; },
        /** cells: array of values or {v, f, s, t}; returns the 0-based row index. */
        row(cells, rowOpts) {
          const r = sh.rows.length;
          sh.rows.push(cells.map(c => (c !== null && typeof c === 'object' && !(c instanceof Date)) ? c : {v: c}));
          if (rowOpts && rowOpts.h) sh.heights[r] = rowOpts.h;
          return r;
        },
        get rowCount() { return sh.rows.length; },
        merge(r1, c1, r2, c2) { sh.merges.push(ref(r1, c1) + ':' + ref(r2, c2)); return api; },
        filter(r1, c1, r2, c2) { sh.filter = ref(r1, c1) + ':' + ref(r2, c2); return api; },
        listValidation(r1, c1, r2, c2, values, prompt) {
          sh.validations.push({sqref: ref(r1, c1) + ':' + ref(r2, c2), values, prompt});
          return api;
        },
        /** rules: [{op:'greaterThan'|'between'|'lessThanOrEqual'|'equal', f:[..], fill, font}] */
        conditional(r1, c1, r2, c2, rules) {
          sh.conditions.push({sqref: ref(r1, c1) + ':' + ref(r2, c2), rules: rules.map(x => Object.assign({}, x, {dxfId: dxf(x)}))});
          return api;
        },
        height(r, h) { sh.heights[r] = h; return api; },
      };
      sheets.push(sh);
      return api;
    }

    function estimateHeight(sh, r) {
      if (sh.heights[r]) return sh.heights[r];
      let lines = 1;
      sh.rows[r].forEach((c, i) => {
        if (c == null || c.v == null || c.f) return;
        const width = (sh.widths[i] || 10) * 1.3;
        const text = String(c.v);
        const n = text.split('\n').reduce((sum, line) => sum + Math.max(1, Math.ceil(line.length / Math.max(4, width))), 0);
        lines = Math.max(lines, n);
      });
      return Math.min(409, Math.round(lines * 12 + 6));
    }

    function cellXml(c, r, i) {
      if (c == null || (c.v == null && c.f == null && c.s == null)) return '';
      const at = ref(r, i);
      const s = c.s ? ' s="' + c.s + '"' : '';
      if (c.f != null) {
        const cached = c.v == null ? '' : (typeof c.v === 'number' ? '<v>' + c.v + '</v>' : '<v>' + esc(c.v) + '</v>');
        const t = typeof c.v === 'string' ? ' t="str"' : '';
        return '<c r="' + at + '"' + s + t + '><f>' + esc(c.f) + '</f>' + cached + '</c>';
      }
      if (c.v == null) return '<c r="' + at + '"' + s + '/>';
      if (typeof c.v === 'number' && isFinite(c.v)) return '<c r="' + at + '"' + s + '><v>' + c.v + '</v></c>';
      return '<c r="' + at + '"' + s + ' t="inlineStr"><is><t xml:space="preserve">' + esc(c.v) + '</t></is></c>';
    }

    function sheetXml(sh, index) {
      const o = sh.opts;
      const maxCols = Math.max(1, ...sh.rows.map(r => r.length), sh.widths.length);
      const dim = 'A1:' + ref(Math.max(0, sh.rows.length - 1), maxCols - 1);
      let x = XML_HEAD + '<worksheet xmlns="' + NS_MAIN + '" xmlns:r="' + NS_REL + '">';
      x += '<sheetPr>' + (o.tabColor ? '<tabColor rgb="' + argb(o.tabColor) + '"/>' : '') +
        (o.fitWidth ? '<pageSetUpPr fitToPage="1"/>' : '') + '</sheetPr>';
      x += '<dimension ref="' + dim + '"/>';
      x += '<sheetViews><sheetView workbookViewId="0"' + (index === 0 ? ' tabSelected="1"' : '') + (o.zoom ? ' zoomScale="' + o.zoom + '"' : '') +
        (o.showGrid === false ? ' showGridLines="0"' : '') + '>';
      if (o.freeze && (o.freeze.row || o.freeze.col)) {
        const fr = o.freeze.row || 0, fc = o.freeze.col || 0;
        const pane = fr && fc ? 'bottomRight' : fr ? 'bottomLeft' : 'topRight';
        x += '<pane' + (fc ? ' xSplit="' + fc + '"' : '') + (fr ? ' ySplit="' + fr + '"' : '') + ' topLeftCell="' + ref(fr, fc) +
          '" activePane="' + pane + '" state="frozen"/><selection pane="' + pane + '" activeCell="' + ref(fr, fc) + '" sqref="' + ref(fr, fc) + '"/>';
      }
      x += '</sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>';
      if (sh.widths.length) {
        x += '<cols>' + sh.widths.map((w, i) => '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + w + '" customWidth="1"/>').join('') + '</cols>';
      }
      x += '<sheetData>';
      sh.rows.forEach((cells, r) => {
        x += '<row r="' + (r + 1) + '" ht="' + estimateHeight(sh, r) + '" customHeight="1">' + cells.map((c, i) => cellXml(c, r, i)).join('') + '</row>';
      });
      x += '</sheetData>';
      if (sh.filter) x += '<autoFilter ref="' + sh.filter + '"/>';
      if (sh.merges.length) x += '<mergeCells count="' + sh.merges.length + '">' + sh.merges.map(m => '<mergeCell ref="' + m + '"/>').join('') + '</mergeCells>';
      let priority = 1;
      sh.conditions.forEach(cf => {
        x += '<conditionalFormatting sqref="' + cf.sqref + '">' + cf.rules.map(rule =>
          '<cfRule type="cellIs" dxfId="' + rule.dxfId + '" priority="' + (priority++) + '" operator="' + rule.op + '">' +
          rule.f.map(f => '<formula>' + esc(f) + '</formula>').join('') + '</cfRule>').join('') + '</conditionalFormatting>';
      });
      if (sh.validations.length) {
        x += '<dataValidations count="' + sh.validations.length + '">' + sh.validations.map(v =>
          '<dataValidation type="list" allowBlank="1" showInputMessage="' + (v.prompt ? 1 : 0) + '" showErrorMessage="1"' +
          (v.prompt ? ' promptTitle="' + esc(v.prompt.title || '') + '" prompt="' + esc(v.prompt.text || '') + '"' : '') +
          ' sqref="' + v.sqref + '"><formula1>"' + esc(v.values.join(',')) + '"</formula1></dataValidation>').join('') + '</dataValidations>';
      }
      x += '<printOptions horizontalCentered="1"/><pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>';
      x += '<pageSetup paperSize="9" orientation="' + (o.landscape ? 'landscape' : 'portrait') + '"' +
        (o.fitWidth ? ' fitToWidth="1" fitToHeight="0"' : '') + '/>';
      if (o.footer || o.header) {
        x += '<headerFooter>' + (o.header ? '<oddHeader>' + esc(o.header) + '</oddHeader>' : '') +
          (o.footer ? '<oddFooter>' + esc(o.footer) + '</oddFooter>' : '') + '</headerFooter>';
      }
      return x + '</worksheet>';
    }

    function bytes() {
      const files = {};
      files['[Content_Types].xml'] = XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
        sheets.map((s, i) => '<Override PartName="/xl/worksheets/sheet' + (i + 1) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join('') +
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>' +
        '</Types>';
      files['_rels/.rels'] = XML_HEAD + '<Relationships xmlns="' + NS_PKG_REL + '">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>' +
        '</Relationships>';
      const created = meta.created || '2026-01-01T00:00:00Z';
      files['docProps/core.xml'] = XML_HEAD + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' +
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
        '<dc:title>' + esc(meta.title || '') + '</dc:title><dc:creator>' + esc(meta.creator || '') + '</dc:creator>' +
        '<dcterms:created xsi:type="dcterms:W3CDTF">' + esc(created) + '</dcterms:created></cp:coreProperties>';
      files['docProps/app.xml'] = XML_HEAD + '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>' +
        esc(meta.application || 'RDXlsx') + '</Application></Properties>';
      const defined = sheets.map((s, i) => s.opts.printTitleRows
        ? '<definedName name="_xlnm.Print_Titles" localSheetId="' + i + '">\'' + esc(s.name).replace(/'/g, "''") + '\'!$' + s.opts.printTitleRows[0] + ':$' + s.opts.printTitleRows[1] + '</definedName>'
        : '').join('') + sheets.map((s, i) => s.filter
        ? '<definedName name="_xlnm._FilterDatabase" localSheetId="' + i + '" hidden="1">\'' + esc(s.name).replace(/'/g, "''") + '\'!' + s.filter.replace(/([A-Z]+)(\d+)/g, '$$$1$$$2') + '</definedName>'
        : '').join('');
      files['xl/workbook.xml'] = XML_HEAD + '<workbook xmlns="' + NS_MAIN + '" xmlns:r="' + NS_REL + '"><bookViews><workbookView/></bookViews><sheets>' +
        sheets.map((s, i) => '<sheet name="' + esc(s.name) + '" sheetId="' + (i + 1) + '" r:id="rId' + (i + 1) + '"/>').join('') + '</sheets>' +
        (defined ? '<definedNames>' + defined + '</definedNames>' : '') + '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>';
      files['xl/_rels/workbook.xml.rels'] = XML_HEAD + '<Relationships xmlns="' + NS_PKG_REL + '">' +
        sheets.map((s, i) => '<Relationship Id="rId' + (i + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet' + (i + 1) + '.xml"/>').join('') +
        '<Relationship Id="rId' + (sheets.length + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';
      files['xl/styles.xml'] = XML_HEAD + '<styleSheet xmlns="' + NS_MAIN + '">' +
        (numFmts.length ? '<numFmts count="' + numFmts.length + '">' + numFmts.map(n => '<numFmt numFmtId="' + n.id + '" formatCode="' + esc(n.code) + '"/>').join('') + '</numFmts>' : '') +
        '<fonts count="' + fonts.length + '">' + fonts.join('') + '</fonts>' +
        '<fills count="' + fills.length + '">' + fills.join('') + '</fills>' +
        '<borders count="' + borders.length + '">' + borders.join('') + '</borders>' +
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
        '<cellXfs count="' + xfs.length + '">' + xfs.join('') + '</cellXfs>' +
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
        '<dxfs count="' + dxfs.length + '">' + dxfs.join('') + '</dxfs></styleSheet>';
      sheets.forEach((s, i) => { files['xl/worksheets/sheet' + (i + 1) + '.xml'] = sheetXml(s, i); });
      return zip(files);
    }

    return {style, dxf, sheet, bytes};
  }

  root.RDXlsx = {workbook, colName, ref, zip, crc32, utf8};
  if (typeof module !== 'undefined' && module.exports) module.exports = root.RDXlsx;
})(typeof globalThis !== 'undefined' ? globalThis : this);
