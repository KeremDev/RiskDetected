INSERT INTO model_pricing_catalog (
  provider,
  model,
  effective_from,
  input_price_per_million,
  output_price_per_million,
  cached_price_per_million,
  thoughts_price_per_million,
  currency,
  notes
)
VALUES (
  'gemini',
  'gemini-2.5-flash-lite',
  CURRENT_DATE,
  0.075,
  0.30,
  0.01875,
  0.30,
  'USD',
  'Gemini 2.5 Flash Lite — admin tahmini maliyet'
)
ON CONFLICT DO NOTHING;;
