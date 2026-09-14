-- Run only in a fresh, disposable local database, never on a project database.
--
-- The P10 second core references four P05 training tables and the training
-- catalogue. A slice that only needs the second core's own tables should not
-- have to apply the whole training and rule chain to get them, so this stands
-- them in with the shape the second core actually reads: a plan to point at, a
-- catalogue code to check, and the session/enrolment/completion chain it
-- counts through. Nothing here is the real training model; P05 owns that.
CREATE TABLE private_isg.training_catalogs(catalog_code text PRIMARY KEY);
CREATE TABLE private_isg.training_plans(plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid,workplace_id uuid);
CREATE TABLE private_isg.training_sessions(session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid REFERENCES private_isg.training_plans(plan_id));
CREATE TABLE private_isg.training_enrolments(enrolment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES private_isg.training_sessions(session_id));
CREATE TABLE private_isg.training_completions(completion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrolment_id uuid REFERENCES private_isg.training_enrolments(enrolment_id));
INSERT INTO private_isg.training_catalogs VALUES ('temel_isg');
