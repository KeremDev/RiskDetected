-- Populated legacy data BEFORE the candidate migrations; never real user data.
INSERT INTO public.companies(id,user_id,name,hazard_class)
VALUES('d1000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000004','Legacy review company','low');
INSERT INTO private_isg.employees(id,company_id,owner_id,employee_code,full_name)
VALUES('d1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001',
'20000000-0000-0000-0000-000000000004','old-1','Legacy employee');
INSERT INTO private_isg.ppe_handovers(handover_id,company_id,employee_id,item,quantity,unit,handed_on,signed_copy,external_ref)
VALUES('d1000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000001',
'd1000000-0000-4000-8000-000000000002','Helmet',1,'piece','2026-09-01',true,'old-paper-reference');
