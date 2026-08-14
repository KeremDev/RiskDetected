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
  'gemini-2.5-flash',
  CURRENT_DATE,
  0.30,
  2.50,
  0.03,
  2.50,
  'USD',
  'Google Gemini API Standard tier (Paid). Kaynak: https://ai.google.dev/gemini-api/docs/pricing — text/image/video input $0.30/M, output (thinking dahil) $2.50/M, context cache $0.03/M.'
);;
