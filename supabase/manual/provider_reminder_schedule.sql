-- OPTIONAL MANUAL SETUP after 043 + Edge deployment. Never run by the agent.
-- First create two Supabase Vault secrets using the Dashboard, not this file:
-- iv_reminder_function_url = https://<project-ref>.supabase.co/functions/v1/iv-provider-reminders
-- iv_reminder_job_secret = SAME 32+ character random value as Edge REMINDER_JOB_SECRET.
-- Enable pg_cron and pg_net through Supabase Extensions first. No real secret belongs in Git.
-- Run once. An existing named job must be reviewed instead of silently replaced.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='iv-provider-payment-reminders') THEN RAISE EXCEPTION 'Reminder schedule already exists; review it before changing';END IF;
 IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name IN ('iv_reminder_function_url','iv_reminder_job_secret'))<>2 THEN RAISE EXCEPTION 'Configure both required Vault secrets first';END IF;
END $guard$;
-- Every 10 minutes permits the first reminder after 24 hours, at/after 09:00 Manila.
-- The service-only RPC deduplicates daily jobs. Access/compensation need no cron job.
SELECT cron.schedule('iv-provider-payment-reminders','*/10 * * * *',$job$
 SELECT net.http_post(
  url:=(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='iv_reminder_function_url'),
  headers:=jsonb_build_object('Content-Type','application/json','x-reminder-secret',(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='iv_reminder_job_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=55000
 );
$job$);
