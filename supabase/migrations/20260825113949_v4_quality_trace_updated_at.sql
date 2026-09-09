-- The authoritative provider-usage trigger updates the quality trace after
-- the engine run totals are finalized. Keep a modification timestamp on that
-- trace so the trigger cannot abort the otherwise atomic v4 finalizer.
alter table private.analysis_quality_trace_v4
  add column if not exists updated_at timestamptz not null default now();

comment on column private.analysis_quality_trace_v4.updated_at is
  'Last authoritative quality-trace synchronization time.';
