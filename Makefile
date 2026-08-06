.PHONY: localization-codegen localization-check localization-inventory localization-test localization-ai-test localization-phase5-test localization-phase5-release-gate localization-phase6-test localization-testflight-status localization-physical-build-status localization-physical-build78-status localization-reviewer-cohort-status localization-wave1-audit localization-ai-canary-preflight localization-ai-canary-keychain-preflight

localization-codegen:
	node scripts/generate_localization_profiles.mjs

localization-inventory:
	node scripts/localization_inventory.mjs --write

localization-check:
	node scripts/generate_localization_profiles.mjs --check
	node scripts/localization_inventory.mjs --check
	node scripts/check_localization_hardcoded.mjs

localization-test: localization-check
	node scripts/localization_profiles_tests.mjs
	node scripts/localization_catalog_tests.mjs
	deno check supabase/functions/_shared/generated/safety-profiles.generated.ts
	$(MAKE) localization-ai-test
	$(MAKE) localization-phase5-test

localization-ai-test:
	deno test --allow-read \
		supabase/functions/_shared/gemini-provider-client_test.ts \
		supabase/functions/_shared/finding-confidence_test.ts \
		supabase/functions/_shared/photo-source-indices_test.ts \
		supabase/functions/_shared/ai-localization-prompt_test.ts \
		supabase/functions/_shared/ai-localization-validation_test.ts \
		supabase/functions/analyze/ai_localization_canary_static_test.ts \
		supabase/functions/analyze/ai_localization_canary_result_contract_test.ts \
		supabase/functions/analyze/localization_phase4_static_test.ts

localization-phase5-test:
	node scripts/localization_phase5_tests.mjs
	node scripts/verify_phase5_external_gates_test.mjs
	node scripts/verify_phase5_external_gates.mjs --mode=current

localization-phase5-release-gate:
	node scripts/verify_phase5_external_gates.mjs --mode=release --live

localization-phase6-test:
	node --test \
		scripts/verify_localization_testflight_rollout_gate_test.mjs \
		scripts/localization_testflight_rollout_test.mjs \
		scripts/collect_build78_physical_smoke_test.mjs \
		scripts/reviewer_localization_cohort_test.mjs \
		scripts/testflight_external_stage9_test.mjs
	deno check \
		supabase/functions/_shared/localization-context-resolver.ts \
		supabase/functions/_shared/ai-localization-validation.ts \
		supabase/functions/analyze/index.ts
	deno test --allow-read \
		supabase/functions/_shared/safety-profile-approval_test.ts \
		supabase/functions/_shared/localization-context-resolver_test.ts \
		supabase/functions/_shared/ai-localization-validation_test.ts \
		supabase/functions/_shared/report-localization_test.ts \
		supabase/functions/_shared/transactional-notification-localization_test.ts \
		supabase/functions/_shared/auth-email-localization_test.ts \
		supabase/functions/_shared/notification-contract_test.ts \
		supabase/functions/send-welcome-email/template_test.ts \
		supabase/functions/generate-excel-report/index_static_test.ts \
		supabase/functions/generate-excel-report/localization_test.ts \
		supabase/functions/analyze/localization_phase6_static_test.ts
	node scripts/run_localization_phase6_pgtap.mjs

localization-testflight-status:
	node scripts/localization_testflight_rollout.mjs verify --expect-incomplete

localization-physical-build-status:
	node scripts/collect_build78_physical_smoke.mjs --expect-hold

localization-physical-build78-status: localization-physical-build-status

localization-reviewer-cohort-status:
	node scripts/reviewer_localization_cohort.mjs status

localization-wave1-audit:
	node --test scripts/verify_wave1_completion_matrix_test.mjs
	node scripts/verify_wave1_completion_matrix.mjs

localization-ai-canary-preflight:
	./scripts/run_ai_localization_canary.mjs --matrix=smoke

localization-ai-canary-keychain-preflight:
	./scripts/run_ai_localization_canary_from_keychain.sh --matrix=smoke
