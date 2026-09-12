import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signedStoragePath, validateStorageObject } from './storage_restore_probe.mjs';

const object = () => ({ bucket: 'photos', name: 'test/photo.jpg', version:'00000000-0000-4000-8000-000000000001', bytes:12, mime:'image/jpeg', cache:'max-age=3600' });
test('Storage restore accepts supported bucket paths and nullable version', () => {
  for (const bucket of ['photos','reports','logos','avatars','legal-documents']) {
    assert.doesNotThrow(() => validateStorageObject({ ...object(), bucket }));
  }
  assert.doesNotThrow(() => validateStorageObject({ ...object(), version: null, bytes: 0 }));
});
for (const [name, change] of [
  ['unknown bucket',{bucket:'unapproved'}],['absolute path',{name:'/tmp/file'}],
  ['parent traversal',{name:'a/../b'}],['dot segment',{name:'./a'}],['empty segment',{name:'a//b'}],
  ['backslash',{name:'a\\b'}],['NUL',{name:'a\0b'}],['non-UUID version',{version:'../a'}],
  ['missing version',{version:undefined}],['oversized file',{bytes:52428801}],['negative size',{bytes:-1}],
  ['fractional size',{bytes:0.5}],['missing MIME',{mime:null}],['MIME header injection',{mime:'image/jpeg\r\nX:bad'}],
  ['cache header injection',{cache:'max-age=3600\nX:bad'}],
]) test(`Storage restore rejects ${name}`, () => {
  assert.throws(() => validateStorageObject({...object(),...change}), /AUTH_RESTORE_STORAGE_OBJECT_INVALID/);
});
test('signed URL remains a relative path to the isolated Storage server', () => {
  assert.equal(signedStoragePath('/object/sign/photos/a.jpg?token=a.b.c'), '/object/sign/photos/a.jpg?token=a.b.c');
  for (const path of ['https://unapproved.example/object/sign/a?token=a.b.c','//unapproved.example/object/sign/a?token=a.b.c',
    '/object/public/a?token=a.b.c','/object/sign/../../health?token=a.b.c','/object/sign/a?token=a.b.c#secret',
    '/object/sign/a?token=a.b.c&token=d.e.f','/object/sign/a?token=a.b.c&redirect=http://example.com',
    '/object/sign/a?token=invalid','/object/sign/a\\b?token=a.b.c',null]) {
    assert.throws(() => signedStoragePath(path), /AUTH_RESTORE_STORAGE_SIGNED_PATH_INVALID/);
  }
});
