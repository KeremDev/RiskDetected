// Independent SQL assertions: no client DTOs or returned success values are trusted.
export function verifyNativeDirectory(sql, company, platform) {
  if (!/^[a-f0-9-]{36}$/.test(company) || !['ios','android'].includes(platform)) throw Error('NATIVE_ORACLE_SCOPE');
  const prefix = `Native ${platform}`;
  const result = JSON.parse(sql(`WITH
    w AS (SELECT * FROM private_isg.workplaces WHERE company_id='${company}' AND name='${prefix} workplace'),
    d AS (SELECT * FROM private_isg.departments WHERE company_id='${company}' AND name='${prefix} department' AND workplace_id IN(SELECT id FROM w)),
    j AS (SELECT * FROM private_isg.job_roles WHERE company_id='${company}' AND title='${prefix} job'),
    o AS (SELECT * FROM private_isg.contractor_organizations WHERE company_id='${company}' AND name='${prefix} contractor'),
    p AS (SELECT * FROM private_isg.employees WHERE company_id='${company}' AND full_name='${prefix} Son'),
    c AS (SELECT * FROM private_isg.workplace_context_versions WHERE workplace_id IN(SELECT id FROM w)),
    a AS (SELECT * FROM private_isg.employee_assignments WHERE employee_id IN(SELECT id FROM p))
    SELECT jsonb_build_object(
      'catalogs',(SELECT count(*) FROM w)=1 AND(SELECT count(*) FROM d)=1 AND(SELECT count(*) FROM j)=1 AND(SELECT count(*) FROM o)=1,
      'engagement',(SELECT count(*) FROM private_isg.contractor_engagements WHERE workplace_id IN(SELECT id FROM w) AND organization_id IN(SELECT id FROM o) AND starts_on='2026-01-01' AND ends_before='2027-01-01')=1,
      'contexts',(SELECT count(*) FROM c)=2 AND(SELECT count(*) FROM c WHERE starts_on='2026-01-01' AND ends_before='2026-06-01')=1 AND(SELECT count(*) FROM c WHERE starts_on='2026-06-01' AND ends_before IS NULL)=1,
      'context_values',(SELECT bool_and(timezone='Europe/Istanbul' AND jurisdiction='TR' AND hazard_class='low' AND evidence_note='Native QA context') FROM c),
      'assignments',(SELECT count(*) FROM a)=2 AND(SELECT count(*) FROM a WHERE starts_on='2026-01-01' AND ends_before='2026-06-01')=1 AND(SELECT count(*) FROM a WHERE starts_on='2026-06-01' AND ends_before IS NULL)=1,
      'snapshots',(SELECT bool_and(department_id IN(SELECT id FROM d) AND job_role_id IN(SELECT id FROM j) AND department_name_snapshot='${prefix} department' AND job_title_snapshot='${prefix} job' AND employer_org_id_snapshot IS NULL) FROM a),
      'employer',(SELECT count(*) FROM p WHERE employer_org_id IN(SELECT id FROM o) AND employer_version=1 AND assignment_version=2)=1);`));
  return {...result,ok:Object.values(result).every(v=>v===true)};
}
