import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT } from './lib.mjs';

const referencePath = 'contracts/isg/v1/design/osgb-nova-reference.json';
export const reference = JSON.parse(readFileSync(resolve(ROOT, referencePath), 'utf8'));
const cap = s => s[0].toUpperCase() + s.slice(1);
export function rgba(value) {
  if (/^#[0-9a-f]{6}$/i.test(value)) return [...[1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16)), 1];
  const m = /^rgba\((\d+),(\d+),(\d+),([.\d]+)\)$/.exec(value);
  if (!m) throw new Error(`Unsupported color: ${value}`);
  const result = m.slice(1).map(Number);
  if (result.slice(0, 3).some(n => n > 255) || result[3] > 1) throw new Error('Color outside range');
  return result;
}

export function tokenModel(input = reference) {
  const t = input.tokens, e = t.roleAccent.expert;
  const palette = dark => {
    const p = { ...(dark ? t.darkBase : t.lightBase), accent: dark ? e.dark : e.light,
      accentInk: e.ink, accentSoft: dark ? e.softDark : e.soft, onAccent: e.onAccent };
    for (const [status, tone] of Object.entries(dark ? t.darkStatus : t.lightStatus)) {
      for (const [part, value] of Object.entries(tone)) p[`status${cap(status)}${cap(part)}`] = value;
    }
    return Object.fromEntries(Object.entries(p).map(([k, v]) => [k, rgba(v)]));
  };
  const families = Object.values(t.novaFont);
  const names = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  const typography = Object.fromEntries(Object.entries(t.novaType).map(([key, s]) => {
    const i = families.indexOf(s.fontFamily);
    if (i < 0) throw new Error('Unknown font');
    return [key, { fontName: `PlusJakartaSans-${names[i]}`, weight: 400 + i * 100,
      size: s.fontSize, tracking: s.letterSpacing ?? 0, lineHeight: s.lineHeight }];
  }));
  const dimensions = {};
  for (const [group, values] of Object.entries({ radius: t.novaRadius, space: t.novaSpace, layout: t.novaLayout })) {
    for (const [k, v] of Object.entries(values)) dimensions[group + cap(k)] = v;
  }
  return { light: palette(false), dark: palette(true), typography, dimensions };
}

export function renderTokens(input = reference) {
  const m = tokenModel(input);
  const header = '// Generated from the pinned OSGB expert reference by scripts/isg/nova_tokens.mjs.\n// No other-role themes, backend rules or runtime activation. Do not edit by hand.\n';
  const decimals = n => Number.isInteger(n) ? `${n}.0` : `${n}`;
  const swiftColor = c => `NovaRGBA(red: ${c[0]}, green: ${c[1]}, blue: ${c[2]}, alpha: ${decimals(c[3])})`;
  const kotlinColor = c => `NovaRGBA(${c[0]}, ${c[1]}, ${c[2]}, ${decimals(c[3])})`;
  const swCases = keys => keys.map(k => `    case ${k}`).join('\n');
  const ktCases = keys => `    ${keys.join(', ')};`;
  const colors = Object.keys(m.light), types = Object.keys(m.typography), dims = Object.keys(m.dimensions);
  const swift = header + `import Foundation

struct NovaRGBA: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double
}

enum NovaColorToken: String, CaseIterable {
${swCases(colors)}

    func rgba(dark: Bool) -> NovaRGBA {
        switch self {
${colors.map(k => `        case .${k}: return dark ? ${swiftColor(m.dark[k])} : ${swiftColor(m.light[k])}`).join('\n')}
        }
    }
}

struct NovaTypeSpec {
    let fontName: String
    let weight: Int
    let size: Double
    let tracking: Double
    let lineHeight: Double
}

enum NovaTypeToken: String, CaseIterable {
${swCases(types)}

    var spec: NovaTypeSpec {
        switch self {
${types.map(k => {const s=m.typography[k]; return `        case .${k}: return NovaTypeSpec(fontName: "${s.fontName}", weight: ${s.weight}, size: ${decimals(s.size)}, tracking: ${decimals(s.tracking)}, lineHeight: ${decimals(s.lineHeight)})`;}).join('\n')}
        }
    }
}

enum NovaDimensionToken: String, CaseIterable {
${swCases(dims)}

    var value: Double {
        switch self {
${dims.map(k => `        case .${k}: return ${decimals(m.dimensions[k])}`).join('\n')}
        }
    }
}
`;
  const kotlin = header + `package com.riskdetectedan.core.designsystem.isg

data class NovaRGBA(val red: Int, val green: Int, val blue: Int, val alpha: Double)

enum class NovaColorToken {
${ktCases(colors)}

    fun rgba(dark: Boolean): NovaRGBA = when (this) {
${colors.map(k => `        ${k} -> if (dark) ${kotlinColor(m.dark[k])} else ${kotlinColor(m.light[k])}`).join('\n')}
    }
}

data class NovaTypeSpec(val fontName: String, val weight: Int, val size: Double, val tracking: Double, val lineHeight: Double)

enum class NovaTypeToken {
${ktCases(types)}

    val spec: NovaTypeSpec get() = when (this) {
${types.map(k => {const s=m.typography[k]; return `        ${k} -> NovaTypeSpec("${s.fontName}", ${s.weight}, ${decimals(s.size)}, ${decimals(s.tracking)}, ${decimals(s.lineHeight)})`;}).join('\n')}
    }
}

enum class NovaDimensionToken {
${ktCases(dims)}

    val value: Double get() = when (this) {
${dims.map(k => `        ${k} -> ${decimals(m.dimensions[k])}`).join('\n')}
    }
}
`;
  return {
    'App/DesignSystem/ISG/NovaTokens.swift': swift,
    'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaTokens.kt': kotlin,
    'contracts/isg/v1/design/nova-native-values.json': JSON.stringify(m, null, 2) + '\n',
  };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  if (process.argv.length !== 3 || process.argv[2] !== '--check') throw new Error('Usage: node scripts/isg/nova_tokens.mjs --check');
  for (const [path, expected] of Object.entries(renderTokens())) {
    if (readFileSync(resolve(ROOT, path), 'utf8') !== expected) throw new Error(`Token drift: ${path}`);
  }
  console.log('PASS: pinned expert tokens match Swift, Kotlin and native test corpus');
}
