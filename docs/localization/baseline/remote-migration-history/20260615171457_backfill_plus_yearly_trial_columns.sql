update public.user_subscriptions
set
  trial_product_id = coalesce(trial_product_id, product_id),
  trial_started_at = coalesce(trial_started_at, created_at),
  trial_ends_at = coalesce(trial_ends_at, current_period_ends_at)
where
  product_id = 'riskdetected_plus_yearly'
  and tier = 'plus'
  and trial_started_at is null
  and current_period_ends_at is not null
  and created_at is not null
  and current_period_ends_at > now()
  and extract(epoch from (current_period_ends_at - created_at)) / 86400 between 6 and 8.5;;
