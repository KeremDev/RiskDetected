alter table public.analyses
drop constraint if exists analyses_analysis_sector_check;

update public.analyses
set
  analysis_sector = null,
  analysis_sector_source = coalesce(analysis_sector_source, 'system_migrated'),
  analysis_sector_prompt_version = null
where analysis_sector is not null
  and analysis_sector not in (
    'general',
    'construction',
    'manufacturing',
    'mining',
    'energy',
    'office',
    'logistics_warehouse',
    'chemical_laboratory',
    'healthcare',
    'food_production',
    'agriculture_livestock',
    'retail',
    'municipal_field_services',
    'education',
    'hospitality'
  );

alter table public.analyses
add constraint analyses_analysis_sector_check
check (
  analysis_sector is null
  or analysis_sector in (
    'general',
    'construction',
    'manufacturing',
    'mining',
    'energy',
    'office',
    'logistics_warehouse',
    'chemical_laboratory',
    'healthcare',
    'food_production',
    'agriculture_livestock',
    'retail',
    'municipal_field_services',
    'education',
    'hospitality'
  )
);
