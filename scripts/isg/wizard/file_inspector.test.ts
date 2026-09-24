import { inspect } from '../../../supabase/functions/_shared/isg/file-format-inspector.ts';

type Runtime = {
  create(bundle: unknown): { generate(answers: unknown, domain: string): unknown };
  exportFile(engine: unknown, snapshot: unknown, format: string): { base64: string };
};
for (const name of ['engine', 'export']) {
  const code = await Deno.readTextFile(new URL(`../../../App/WizardAssets/isg_wizard/${name}.js`, import.meta.url));
  new Function(code)();
}
const runtime = (globalThis as unknown as { ISGWizard: Runtime }).ISGWizard;
const bundle = JSON.parse(await Deno.readTextFile(new URL('../../../App/WizardAssets/isg_wizard/isgada-catalog.json', import.meta.url)));
const engine = runtime.create(bundle);
for (const domain of ['risk','emergency']) for (const format of ['docx','xlsx']) {
  Deno.test(`${domain} ${format} passes existing file archive inspector`, () => {
    const snapshot = engine.generate({ sectors: ['S172'], areas: ['office'] }, domain);
    const file = runtime.exportFile(engine, snapshot, format);
    const bytes = Uint8Array.from(atob(file.base64), c => c.charCodeAt(0));
    const result = inspect({ bytes, declaredExtension: format, declaredBytes: bytes.length,
      declaredSha256: 'a'.repeat(64), actualSha256: 'a'.repeat(64) });
    if (result.verdict !== 'clean') throw Error(JSON.stringify(result));
  });
}
