UPDATE user_subscriptions
SET
  trial_product_id = COALESCE(trial_product_id, product_id),
  trial_started_at = COALESCE(trial_started_at, created_at),
  trial_ends_at = COALESCE(trial_ends_at, current_period_ends_at)
WHERE
  product_id = 'riskdetected_plus_yearly'
  AND tier = 'plus'
  AND trial_started_at IS NULL
  AND current_period_ends_at IS NOT NULL
  AND created_at IS NOT NULL
  AND current_period_ends_at > NOW()
  AND EXTRACT(EPOCH FROM (current_period_ends_at - created_at)) / 86400 BETWEEN 6 AND 8.5;;
