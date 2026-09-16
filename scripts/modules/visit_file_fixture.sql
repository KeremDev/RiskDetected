-- Only in run_pilot's disposable local DB. Prior module fixtures do not include P04.
CREATE TABLE private_isg.file_assets(asset_id uuid PRIMARY KEY,owner_id uuid NOT NULL,company_id uuid NOT NULL,detected_type text NOT NULL,scan_status text NOT NULL);
CREATE TABLE private_isg.file_library_entries(entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),asset_id uuid NOT NULL REFERENCES private_isg.file_assets,
 owner_id uuid NOT NULL,company_id uuid NOT NULL,is_archived boolean NOT NULL DEFAULT false,created_at timestamptz DEFAULT now());
