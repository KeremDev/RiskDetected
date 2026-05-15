
-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- Enums
create type risk_level as enum ('critical', 'high', 'medium', 'low', 'unknown');
create type risk_method as enum ('fine_kinney', 'matrix_5x5');
create type analysis_status as enum ('pending', 'analyzing', 'completed', 'failed');
create type analysis_kind as enum ('photo', 'text');
create type canvas_id as enum ('general', 'ppe', 'mark', 'sector', 'urgent', 'procedure');
create type subscription_tier as enum ('free', 'pro');
create type subscription_period as enum ('monthly', 'yearly');
create type analysis_review_status as enum ('open', 'reviewed', 'closed');
;
