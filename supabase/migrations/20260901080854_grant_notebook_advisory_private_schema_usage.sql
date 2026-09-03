-- The notebook advisory RPCs remain SECURITY INVOKER by design. PostgREST calls
-- them as service_role, so that role also needs schema USAGE in addition to
-- the narrowly-scoped table and function grants from the contract migration.
grant usage on schema private to service_role;
