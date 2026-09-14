-- Narrow dependency doubles for the link boundary; upload/scanner behavior is
-- validated by the separate file-library suite, not simulated here.
CREATE TABLE private_isg.file_library_entries (
 entry_id uuid PRIMARY KEY,company_id uuid,owner_id uuid,asset_id uuid,title text,is_archived boolean DEFAULT false
);
CREATE FUNCTION private_isg.require_file_library_company(uuid,boolean) RETURNS uuid LANGUAGE sql AS $$
 SELECT private_isg.require_katip_company($1,$2)
$$;
