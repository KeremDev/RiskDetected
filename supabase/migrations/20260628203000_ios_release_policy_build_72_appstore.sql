-- Post–App Store release cosmetic label: TestFlight tag -> App Store tag.
-- latest_build was already 72 from allow_multi_photo_build_72 migration.

update public.app_feature_flags
set value = jsonb_set(value, '{policy_version}', '"build-72-appstore"'::jsonb, true),
    updated_at = now()
where key = 'ios_release_policy';
