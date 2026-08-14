update public.user_subscriptions
set will_renew = true
where
  trial_product_id = 'riskdetected_plus_yearly'
  and tier = 'plus'
  and will_renew is null
  and trial_ends_at is not null
  and trial_ends_at > now();;
