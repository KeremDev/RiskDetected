-- Cover the foreign-key lookup paths used by cascades and lazy projections.
-- These indexes are intentionally additive and do not change result-hub access.

create index if not exists analysis_notebook_entry_revisions_analysis_idx
  on private.analysis_notebook_entry_revisions (analysis_id);

create index if not exists analysis_notebook_entry_revisions_user_idx
  on private.analysis_notebook_entry_revisions (user_id);

create index if not exists analysis_item_feedback_analysis_idx
  on private.analysis_item_feedback (analysis_id);

create index if not exists analysis_item_feedback_public_finding_idx
  on private.analysis_item_feedback (public_finding_id)
  where public_finding_id is not null;

create index if not exists analysis_item_feedback_notebook_entry_idx
  on private.analysis_item_feedback (notebook_entry_id)
  where notebook_entry_id is not null;

create index if not exists analysis_result_events_analysis_idx
  on private.analysis_result_events (analysis_id)
  where analysis_id is not null;

create index if not exists report_export_intents_analysis_idx
  on private.report_export_intents (analysis_id);
