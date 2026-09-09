-- Training recommendations became a first-class result-hub section after the
-- original event ledger was created. Keep the analytics constraint aligned
-- with the result, feedback, and paywall contracts so existing mobile builds
-- can persist section-selection and funnel events.
alter table private.analysis_result_events
  drop constraint if exists analysis_result_events_section_check;

alter table private.analysis_result_events
  add constraint analysis_result_events_section_check
    check (
      section is null
      or section in (
        'risk_analysis',
        'expert_recommendations',
        'training_recommendations',
        'approved_notebook'
      )
    );
