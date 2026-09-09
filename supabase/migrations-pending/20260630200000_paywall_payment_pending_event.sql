alter table public.paywall_events
  drop constraint if exists paywall_events_event_name_check;

alter table public.paywall_events
  add constraint paywall_events_event_name_check
    check (
      event_name in (
        'entry_tap',
        'view',
        'close',
        'cta_tap',
        'plan_select',
        'billing_select',
        'purchase_started',
        'purchase_succeeded',
        'purchase_failed',
        'purchase_cancelled',
        'payment_pending',
        'restore_tap',
        'personal_plan_view',
        'personal_plan_continue',
        'trial_invite_view',
        'trial_invite_cta_tap'
      )
    );
