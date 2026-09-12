/** Real GoTrue probes, only called inside the owned network-none synthetic harness.
 * No token/password/body is returned, persisted, logged or included in assertion messages.
 */
export function probePasswordAuth({ synthetic, request, admin, pass }) {
  if (synthetic !== true) throw new Error('AUTH_RESTORE_PASSWORD_SYNTHETIC_REQUIRED');
  const email = 'password-contract@example.invalid';
  let password = 'InitialPassword1';
  const created = request('/admin/users', { method:'POST', token:admin, body:{ email, password, email_confirm:true } });
  pass('password_fixture_created', [200,201].includes(created.status) && /^[a-f0-9-]{36}$/.test(created.body.id ?? ''));
  const id = created.body.id;
  const login = value => request('/token?grant_type=password', { method:'POST', body:{email,password:value} });
  let session = login(password);
  pass('password_fixture_login',session.status === 200 && session.body.user?.id === id);
  const cases = [
    ['missing_uppercase','abcdefgh1',false], ['missing_lowercase','ABCDEFGH1',false],
    ['missing_digit','Abcdefgh',false], ['seven_ascii','Abcdef1',false],
    ['eight_ascii','Abcdefg1',true], ['whitespace_preserved',' Abcdefg1 ',true],
    ['turkish_extra','Ab1şifreİ',true], ['decomposed_extra','Ab1e\u0301xyz',true],
    ['ascii_72','Aa1'+'x'.repeat(69),true], ['ascii_73','Aa1'+'x'.repeat(70),false],
    ['unicode_72_bytes','Aa1x'+'ş'.repeat(34),true], ['unicode_74_bytes','Aa1x'+'ş'.repeat(35),false],
    // Documents the server mismatch: 5 Unicode scalars, 11 UTF-8 bytes meets min_length=8.
    ['server_counts_bytes_not_characters','Ab1🔐🔐',true],
  ];
  for (const [name,candidate,accepted] of cases) {
    const result = request('/user', {method:'PUT',token:session.body.access_token,body:{password:candidate}});
    pass(`password_${name}_${accepted?'accepted':'rejected'}`,accepted ? result.status === 200 && result.body.id === id : [400,422].includes(result.status));
    if (accepted) password = candidate;
    const refreshed = login(password);
    pass(`password_${name}_same_uuid`,refreshed.status === 200 && refreshed.body.user?.id === id);
    session = refreshed;
    if (name === 'whitespace_preserved') pass('password_trimmed_variant_rejected',login(candidate.trim()).status === 400);
    if (name === 'decomposed_extra') pass('password_normalized_variant_rejected',login(candidate.normalize('NFC')).status === 400);
  }
  pass('password_update_requires_session',[401,403].includes(request('/user',{method:'PUT',body:{password:'NewPassword1'}}).status));
  pass('password_update_keeps_email',request('/user',{token:session.body.access_token}).body.email === email);
  pass('password_fixture_removed', [200,204].includes(request(`/admin/users/${id}`,{method:'DELETE',token:admin}).status));
  return {cases:cases.length, max_utf8_bytes:72, server_minimum_uses:'utf8_bytes',
    product_minimum_characters_enforced_by_server:false, production_auth_settings_changed:false,
    signup_email_recovery_mfa_tested:false};
}
