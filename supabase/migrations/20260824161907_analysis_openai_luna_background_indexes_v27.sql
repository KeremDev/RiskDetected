-- Cover the three non-leading foreign keys reported by Supabase advisor.
-- The engine_run_id foreign key is already covered by the unique logical-key
-- index created in v26.
create index if not exists analysis_openai_background_analysis_idx
  on private.analysis_openai_background_responses (analysis_id);
create index if not exists analysis_openai_background_user_idx
  on private.analysis_openai_background_responses (user_id);
create index if not exists analysis_openai_background_photo_run_idx
  on private.analysis_openai_background_responses (photo_run_id);
