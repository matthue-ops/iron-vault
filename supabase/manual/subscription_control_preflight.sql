-- READ ONLY. Run before 048 and save the results. No records changed.
-- Existing access dependent on pending verification will end at the normal period/grace boundary.
SELECT s.tenant_id,g.gym_name,s.owner_id,
 ironvault_private.subscription_state(s.tenant_id) AS current_access,
 ironvault_private.subscription_state_043_base(s.tenant_id) AS period_and_grace_only
FROM ironvault_private.gym_subscriptions s JOIN public.owners g ON g.id=s.tenant_id
WHERE ironvault_private.subscription_state(s.tenant_id) IS DISTINCT FROM ironvault_private.subscription_state_043_base(s.tenant_id);
SELECT r.id,r.tenant_id,r.kind,r.confirmed_at,r.quote,r.payment_reference,v.status AS verification_status,v.submitted_at,
 CASE WHEN v.request_id IS NOT NULL THEN ironvault_private.verification_delay_days(v.request_id,clock_timestamp()) ELSE 0 END AS legacy_delay_days_to_review
FROM ironvault_private.subscription_requests r LEFT JOIN ironvault_private.payment_verifications v ON v.request_id=r.id
WHERE r.approved_at IS NULL AND r.cancelled_at IS NULL ORDER BY r.tenant_id,r.confirmed_at;
SELECT a.tenant_id,a.id AS first_period,b.id AS second_period,a.start_date,a.end_date,b.start_date AS next_start,b.end_date AS next_end
FROM ironvault_private.subscription_periods a JOIN ironvault_private.subscription_periods b ON a.tenant_id=b.tenant_id AND a.id<b.id
WHERE daterange(a.start_date,a.end_date,'[]')&&daterange(b.start_date,b.end_date,'[]');
SELECT id,effective_date,data->>'paid_days' AS paid_days,data->>'dashboard_price' AS dashboard_price,data->>'portal_price' AS portal_price
FROM ironvault_private.service_versions WHERE NOT retired ORDER BY effective_date DESC;
