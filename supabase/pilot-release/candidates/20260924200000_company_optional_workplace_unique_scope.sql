-- PostgreSQL treats NULL as distinct in the older workplace-scoped unique keys.
-- Keep company-wide identities unique without changing existing workplace keys.
BEGIN;
CREATE UNIQUE INDEX annual_work_plans_company_general_unique
  ON private_isg.annual_work_plans(company_id,plan_year)
  WHERE workplace_id IS NULL AND NOT is_deleted;
CREATE UNIQUE INDEX departments_company_general_code_unique
  ON private_isg.departments(company_id,code)
  WHERE workplace_id IS NULL;
CREATE UNIQUE INDEX curriculum_company_general_active_unique
  ON private_isg.company_curriculum_versions(company_id,catalog_code,scope_key)
  WHERE workplace_id IS NULL AND state='active';
COMMIT;
