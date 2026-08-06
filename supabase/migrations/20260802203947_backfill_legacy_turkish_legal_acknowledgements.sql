-- Preserve historical Turkish "seen" acknowledgements after legal document-set
-- metadata became part of the client lookup. These rows were created before
-- document_set_id/document_locale existed, so the current iOS client otherwise
-- treats an already-seen document version as a new update on every launch.

update public.legal_document_acknowledgements
set
  document_set_id = 'tr-current',
  document_locale = 'tr'
where document_set_id is null
  and document_locale is null
  and document_kind in ('terms', 'privacy', 'kvkk', 'consent')
  and version ~ '^(terms|privacy|kvkk|consent)-[0-9]{4}-[0-9]{2}-[0-9]{2}([.][0-9]+)?$';
