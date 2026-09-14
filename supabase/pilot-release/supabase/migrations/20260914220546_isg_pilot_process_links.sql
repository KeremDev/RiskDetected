-- Deleted engagements remain in history without reserving their date range.
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='private_isg.contractor_engagements'::regclass AND contype='x' LOOP
  EXECUTE format('ALTER TABLE private_isg.contractor_engagements DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
ALTER TABLE private_isg.contractor_engagements ADD CONSTRAINT contractor_engagements_active_dates
 EXCLUDE USING gist(company_id WITH =,organization_id WITH =,workplace_id WITH =,effective_dates WITH &&) WHERE (NOT is_deleted);
ALTER TABLE private_isg.process_record_meta ADD CONSTRAINT process_related_pair
 CHECK ((related_kind IS NULL) = (related_id IS NULL));
ALTER TABLE private_isg.process_record_meta ADD CONSTRAINT process_related_not_self
 CHECK (related_id IS NULL OR kind<>related_kind OR record_id<>related_id);
