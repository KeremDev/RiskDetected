/** All requests and mail retrieval are injected by the guarded network-none runner. */
export function probeSignupRecovery({synthetic, request, mailbox, admin, pass}) {
  if (synthetic !== true) throw new Error('AUTH_RESTORE_EMAIL_SYNTHETIC_REQUIRED');
  const email = 'signup-contract@example.invalid', password = 'SignupPassword1';
  const signup = request('/signup',{method:'POST',body:{email,password}});
  pass('signup_requires_confirmation',signup.status === 200 && !!signup.body.id && !signup.body.access_token && !signup.body.email_confirmed_at);
  const id = signup.body.id;
  pass('unconfirmed_password_login_rejected', request('/token?grant_type=password',{method:'POST',body:{email,password}}).status === 400);
  const code = purpose => {
    const messages = mailbox().filter(m=>m.recipient.includes(email));
    const token = messages.at(-1)?.body.match(/TEST-CODE:\s*(\d{6,10})/)?.[1];
    pass(`${purpose}_local_smtp_code_received`,typeof token === 'string');
    return token;
  };
  const signupCode = code('signup');
  pass('signup_code_wrong_purpose_rejected',request('/verify',{method:'POST',body:{email,token:signupCode,type:'recovery'}}).status >= 400);
  pass('signup_code_foreign_email_rejected',request('/verify',{method:'POST',body:{email:'foreign-contract@example.invalid',token:signupCode,type:'email'}}).status >= 400);
  pass('signup_bad_code_rejected',request('/verify',{method:'POST',body:{email,token:'0000000000',type:'email'}}).status >= 400);
  const verified = request('/verify',{method:'POST',body:{email,token:signupCode,type:'email'}});
  pass('signup_email_code_keeps_uuid',verified.status === 200 && verified.body.user?.id === id && !!verified.body.access_token);
  pass('signup_code_single_use',request('/verify',{method:'POST',body:{email,token:signupCode,type:'email'}}).status >= 400);
  pass('confirmed_password_login',request('/token?grant_type=password',{method:'POST',body:{email,password}}).body.user?.id === id);
  const recovered = request('/recover',{method:'POST',body:{email}});
  pass('recovery_request_accepted', recovered.status === 200);
  const recoveryCode = code('recovery');
  pass('recovery_code_is_not_signup_code',recoveryCode !== signupCode);
  pass('recovery_code_wrong_purpose_rejected',request('/verify',{method:'POST',body:{email,token:recoveryCode,type:'signup'}}).status >= 400);
  pass('recovery_code_foreign_email_rejected',request('/verify',{method:'POST',body:{email:'foreign-contract@example.invalid',token:recoveryCode,type:'recovery'}}).status >= 400);
  // Purpose-specific recovery code verification; do not mark fresh auth from a URL alone.
  const recovery = request('/verify',{method:'POST',body:{email,token:recoveryCode,type:'recovery'}});
  pass('recovery_code_same_uuid',recovery.status === 200 && recovery.body.user?.id === id && !!recovery.body.access_token);
  pass('recovery_code_single_use',request('/verify',{method:'POST',body:{email,token:recoveryCode,type:'recovery'}}).status >= 400);
  const next = 'ReplacementPassword2';
  pass('recovery_password_updated_same_uuid',request('/user',{method:'PUT',token:recovery.body.access_token,body:{password:next}}).body.id === id);
  pass('recovery_old_password_rejected',request('/token?grant_type=password',{method:'POST',body:{email,password}}).status === 400);
  pass('recovery_new_password_same_uuid',request('/token?grant_type=password',{method:'POST',body:{email,password:next}}).body.user?.id === id);
  const missing = request('/recover',{method:'POST',body:{email:'missing-contract@example.invalid'}});
  pass('recovery_existing_and_missing_share_generic_response',missing.status === recovered.status && JSON.stringify(missing.body) === JSON.stringify(recovered.body));
  pass('signup_recovery_fixture_removed',[200,204].includes(request(`/admin/users/${id}`,{method:'DELETE',token:admin}).status));
  return {local_smtp_only:true, email_confirmation:true, signup_otp_type:'email', recovery_otp_type:'recovery',
    same_uuid:true, single_use:true, production_hook_provider_delivery_tested:false, pkce_deep_link_mfa_tested:false,
    recovery_timing_enumeration_tested:false};
}
