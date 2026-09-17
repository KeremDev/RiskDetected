# Workspace context v1 transport

This response contract separates authenticated actor identity from the selected personal or OSGB workspace. It mirrors `isg_workspace_context_v1`; parsing validates transport integrity only and never grants access.

The server derives membership and capabilities from current database state. Clients key caches and pending work with `workspace_id`, `membership.permission_revision`, and their session epoch. A workspace switch invalidates old responses before loading the next scope. Unknown fields, unsafe integers, impossible role/status combinations, and capability values inconsistent with the membership are rejected.

Personal context remains a single active owner membership. A `pending_purchase` OSGB is readable for setup but cannot operate domain records. A suspended or ended membership has no capability. Practicing status is valid only for an active OSGB member; an operational owner/admin therefore consumes a seat too.
