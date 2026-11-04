-- MANUAL ONLY after 028. Correct NEW pass durations; never shorten existing passes.
BEGIN;
CREATE OR REPLACE FUNCTION ironvault_private.plan_terms(p_member text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; pricing jsonb; price numeric; discount numeric; days integer; key text;
BEGIN
 SELECT * INTO STRICT m FROM public.members WHERE id=p_member;
 SELECT o.pricing INTO STRICT pricing FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE';
 CASE p_plan WHEN '1-Day Pass' THEN key:='day';days:=0;
 WHEN '1-Week Pass' THEN key:='week';days:=6;
 WHEN '1-Month Unlimited' THEN key:='month';days:=29;
 ELSE RAISE EXCEPTION 'Unsupported plan'; END CASE;
 price:=(pricing->>key)::numeric;discount:=coalesce(m.discount_percentage,0);
 IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<=0 OR price>10000000
 OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>=100 THEN
  RAISE EXCEPTION 'Invalid configured price or discount';
 END IF;
 -- Preserve existing desk discounted-price whole-peso rounding. Zero-price
 -- entitlements require a separate explicit complimentary-plan workflow.
 IF discount>0 THEN price:=round(price*(1-discount/100)); END IF;
 IF price<=0 OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid configured monetary precision'; END IF;
 RETURN jsonb_build_object('price',price,'expiration_date',
  ((now() AT TIME ZONE 'Asia/Manila')::date+days)::text,'wallet_balance',coalesce(m.wallet_balance,0));
END $fn$;

ALTER FUNCTION ironvault_private.plan_terms(text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.plan_terms(text,text) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.iv_attendance_logs ADD COLUMN IF NOT EXISTS membership_snapshot jsonb;
-- Intentionally no backfill: current membership is not reliable historical evidence.
CREATE OR REPLACE FUNCTION ironvault_private.capture_attendance_membership()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; business_day date; expiry date;
BEGIN
 SELECT * INTO STRICT m FROM public.members WHERE id=NEW.member_id AND tenant_id=NEW.tenant_id FOR SHARE;
 business_day:=(NEW.created_at AT TIME ZONE 'Asia/Manila')::date;
 IF business_day IS NULL THEN RAISE EXCEPTION 'Attendance timestamp required'; END IF;
 -- The admission function has already validated the entitlement. Never accept a client-supplied snapshot.
 expiry:=m.expiration_date::date;
 NEW.membership_snapshot:=jsonb_build_object('version',1,'business_day',business_day::text,
  'plan',m.plan,'expiration_date',expiry::text,'days_remaining',greatest(0,expiry-business_day),'status',m.status);
 RETURN NEW;
END $fn$;
ALTER FUNCTION ironvault_private.capture_attendance_membership() OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.capture_attendance_membership() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS iv_capture_attendance_membership ON public.iv_attendance_logs;
CREATE TRIGGER iv_capture_attendance_membership BEFORE INSERT ON public.iv_attendance_logs
 FOR EACH ROW EXECUTE FUNCTION ironvault_private.capture_attendance_membership();
-- iv_report_snapshot already serializes attendance using to_jsonb(x), so the new field is included.
NOTIFY pgrst,'reload schema';
COMMIT;
