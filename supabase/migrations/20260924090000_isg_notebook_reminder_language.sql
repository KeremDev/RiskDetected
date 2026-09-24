-- The notebook reminder push was written in Turkish for every recipient. The
-- delivery snapshot now also returns the owner's app language, so
-- process-notebook-reminders can pick the Turkish or English copy from
-- _shared/user-facing-copy.ts. The profile is joined optionally: a missing
-- profile or language still delivers, in Turkish, exactly as before. Every
-- other field, filter and grant is unchanged.
CREATE OR REPLACE FUNCTION public.isg_notebook_delivery_snapshot_v1(p_id uuid,p_claim uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private_isg.notes_gate(false);
 SELECT jsonb_build_object('token',t.token,'environment',t.environment,'application_id',t.application_id,
   'provider',t.provider,'occurrence_id',o.occurrence_id,'language',pr.app_language)
 INTO result FROM private_isg.notebook_deliveries d
 JOIN private_isg.reminder_occurrences o ON o.occurrence_id=d.occurrence_id
 JOIN private_isg.personal_reminders r USING(reminder_id)
 JOIN private_isg.device_delivery_claims c USING(reminder_id)
 JOIN public.push_device_tokens t ON t.user_id=r.owner_id AND t.installation_id=c.installation_id
 JOIN private_isg.notification_device_permissions p ON p.token_id=t.id AND p.owner_id=r.owner_id
 JOIN public.notification_preferences prefs ON prefs.user_id=r.owner_id
 JOIN auth.sessions s ON s.id=p.session_id AND s.user_id=r.owner_id
 JOIN auth.users u ON u.id=r.owner_id
 LEFT JOIN public.profiles pr ON pr.id=r.owner_id
 WHERE d.id=p_id AND d.claim_token=p_claim AND d.state='claimed' AND d.created_at>clock_timestamp()-interval '5 minutes'
   AND r.state='active' AND o.state IN ('scheduled','snoozed') AND d.effective_due_at=coalesce(o.snoozed_until,o.due_at)
   AND c.strategy='server_push' AND t.notifications_enabled AND p.os_authorized
   AND p.token_fingerprint=md5(t.token) AND prefs.enabled AND prefs.app_reminders
   AND (s.not_after IS NULL OR s.not_after>clock_timestamp()) AND u.deleted_at IS NULL
   AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp()) AND NOT u.is_anonymous
   AND t.provider='apns' AND t.application_id IN ('com.riskdetected.app','com.riskdetected.app.osgbpilot')
 ORDER BY p.observed_at DESC LIMIT 1;
 RETURN result;
END $$;
