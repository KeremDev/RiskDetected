# Account Deletion Live QA - 2026-05-30

Generated: 2026-05-30 Europe/Istanbul

## Summary

- PASS: `request-account-deletion` deployed and active.
- PASS: `account-deletion-complete` redeployed with `--no-verify-jwt`.
- PASS: temp user deletion through client-callable JWT flow returned `200`.
- PASS: response included `completed=true` and `auth_user_deleted=true`.
- PASS: temp auth user no longer existed after deletion.
- PASS: deleted user's previous JWT returned `403` from `/auth/v1/user`.
- PASS: tokensiz `request-account-deletion` returned `401`.

## Notes

Initial live attempt exposed that `request-account-deletion` was not deployed, then that the privileged worker was still gateway-blocked with `401`. After deploying `request-account-deletion` and redeploying `account-deletion-complete --no-verify-jwt`, the full temp-user deletion path passed.
