CREATE TABLE private_isg.contractor_organizations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 code text NOT NULL CHECK(btrim(code)<>''),name text NOT NULL CHECK(btrim(name)<>''),
 relationship text NOT NULL CHECK(relationship IN('subcontractor','contractor','supplier','other')),
 is_archived boolean NOT NULL DEFAULT false,version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
 UNIQUE(company_id,id),UNIQUE(company_id,code),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.contractor_engagements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 organization_id uuid NOT NULL,workplace_id uuid NOT NULL,starts_on date NOT NULL CHECK(isfinite(starts_on)),
 ends_before date CHECK(isfinite(ends_before) AND ends_before>starts_on),
 effective_dates daterange GENERATED ALWAYS AS(daterange(starts_on,ends_before,'[)')) STORED,
 description text NOT NULL DEFAULT '',version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
 UNIQUE(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,organization_id) REFERENCES private_isg.contractor_organizations(company_id,id),
 FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id),
 EXCLUDE USING gist(company_id WITH =,organization_id WITH =,workplace_id WITH =,effective_dates WITH &&)
);
ALTER TABLE private_isg.employees ADD COLUMN employer_org_id uuid;