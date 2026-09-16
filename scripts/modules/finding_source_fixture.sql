CREATE TABLE public.analyses(id uuid PRIMARY KEY,user_id uuid NOT NULL);
CREATE TABLE public.findings(id uuid PRIMARY KEY,analysis_id uuid,user_id uuid,title text,description text,recommended_action text,references_text text,responsible text,
 fk_probability numeric,fk_frequency numeric,fk_severity numeric,fk_score numeric,fk_band text,m5_probability int,m5_severity int,m5_score int,m5_band text,
 photo_id uuid,is_user_deleted bool DEFAULT false,is_scored bool DEFAULT true,finding_version int DEFAULT 1);
