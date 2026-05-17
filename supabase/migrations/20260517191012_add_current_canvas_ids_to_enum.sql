-- Keep public.canvas_id aligned with the active iOS AnalysisCanvas ids.
-- Without these values, paid/TestFlight users can select a newer canvas in
-- the app and fail before the analyze Edge Function is reached.

alter type public.canvas_id add value if not exists 'machine';
alter type public.canvas_id add value if not exists 'warning_signs';
alter type public.canvas_id add value if not exists 'electrical';
alter type public.canvas_id add value if not exists 'fire';
alter type public.canvas_id add value if not exists 'ergonomics';
alter type public.canvas_id add value if not exists 'environment_measurement';
alter type public.canvas_id add value if not exists 'explosion';
alter type public.canvas_id add value if not exists 'environment';
alter type public.canvas_id add value if not exists 'legislation';
alter type public.canvas_id add value if not exists 'working_at_height';
alter type public.canvas_id add value if not exists 'mobile_equipment';
alter type public.canvas_id add value if not exists 'general_premium';
alter type public.canvas_id add value if not exists 'construction_machinery';
