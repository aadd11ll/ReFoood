-- Review before running in the existing ReFood project.
-- Adds RLS policies, new demo functions and replaces two existing summary functions.
-- No table/column is created or dropped; no existing row or sensor reading is changed.
-- It enables RLS on pickup_locations and changes permissions/policies/functions.
-- Prerequisite: create Supabase Auth users with verified emails matching public.users.email.
-- Sign in with a Donor account for writes and a Recipient account for bookings.

BEGIN;

-- The original screenshots did not include pickup_locations RLS state.
ALTER TABLE public.pickup_locations ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.users, public.pickup_locations,
  public.food_listings, public.food_claims, public.smart_food_sensors FROM anon;
GRANT SELECT ON public.users, public.pickup_locations, public.food_listings,
  public.food_claims, public.smart_food_sensors TO authenticated;
GRANT INSERT ON public.pickup_locations, public.food_listings TO authenticated;
REVOKE UPDATE ON public.food_listings FROM PUBLIC, anon, authenticated;
GRANT UPDATE(status), DELETE ON public.food_listings TO authenticated;
DO $$ DECLARE seq_name text; BEGIN
  SELECT pg_get_serial_sequence('public.food_listings','listing_id') INTO seq_name;
  IF seq_name IS NOT NULL THEN
    EXECUTE format('GRANT USAGE ON SEQUENCE %s TO authenticated', seq_name);
  END IF;
  SELECT pg_get_serial_sequence('public.pickup_locations','location_id') INTO seq_name;
  IF seq_name IS NOT NULL THEN
    EXECUTE format('GRANT USAGE ON SEQUENCE %s TO authenticated', seq_name);
  END IF;
END $$;

-- A caller can prove only their own existing ReFood identity.
CREATE OR REPLACE FUNCTION public.refood_is_user(p_user_id integer, p_role text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM auth.users a
    WHERE a.id = auth.uid() AND a.email_confirmed_at IS NOT NULL
  ) AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.user_id = p_user_id
      AND lower(u.email) = lower(auth.jwt() ->> 'email')
      AND u.role = p_role
  );
$$;
REVOKE ALL ON FUNCTION public.refood_is_user(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_is_user(integer, text) TO authenticated;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='ReFood own identity') THEN
    CREATE POLICY "ReFood own identity" ON public.users FOR SELECT TO authenticated
      USING (public.refood_is_user(user_id, role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pickup_locations' AND policyname='ReFood pickup locations for signed-in users') THEN
    CREATE POLICY "ReFood pickup locations for signed-in users" ON public.pickup_locations FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pickup_locations' AND policyname='ReFood donor creates own pickup location') THEN
    CREATE POLICY "ReFood donor creates own pickup location" ON public.pickup_locations FOR INSERT TO authenticated
      WITH CHECK (public.refood_is_user(donor_id, 'Donor'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='food_listings' AND policyname='ReFood donor reads own listings') THEN
    CREATE POLICY "ReFood donor reads own listings" ON public.food_listings FOR SELECT TO authenticated
      USING (public.refood_is_user(donor_id, 'Donor'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='food_listings' AND policyname='ReFood donor inserts own listing') THEN
    CREATE POLICY "ReFood donor inserts own listing" ON public.food_listings FOR INSERT TO authenticated
      WITH CHECK (public.refood_is_user(donor_id, 'Donor') AND status = 'Available'
        AND title LIKE 'EXAM TEST %'
        AND expiry_timestamp > now()
        AND EXISTS (SELECT 1 FROM public.pickup_locations p
                    WHERE p.location_id = food_listings.location_id
                      AND p.donor_id = food_listings.donor_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='food_listings' AND policyname='ReFood donor updates own listing') THEN
    CREATE POLICY "ReFood donor updates own listing" ON public.food_listings FOR UPDATE TO authenticated
      USING (public.refood_is_user(donor_id, 'Donor') AND title LIKE 'EXAM TEST %'
        AND status = 'Available')
      WITH CHECK (public.refood_is_user(donor_id, 'Donor') AND title LIKE 'EXAM TEST %'
        AND status IN ('Reserved', 'Expired'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='food_listings' AND policyname='ReFood donor deletes own listing') THEN
    CREATE POLICY "ReFood donor deletes own listing" ON public.food_listings FOR DELETE TO authenticated
      USING (public.refood_is_user(donor_id, 'Donor') AND title LIKE 'EXAM TEST %'
        AND NOT EXISTS (SELECT 1 FROM public.food_claims c
                        WHERE c.listing_id = food_listings.listing_id)
        AND NOT EXISTS (SELECT 1 FROM public.smart_food_sensors s
                        WHERE s.listing_id = food_listings.listing_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='food_claims' AND policyname='ReFood recipient and donor read claims') THEN
    CREATE POLICY "ReFood recipient and donor read claims" ON public.food_claims FOR SELECT TO authenticated
      USING (public.refood_is_user(recipient_id, 'Recipient') OR EXISTS
        (SELECT 1 FROM public.food_listings f WHERE f.listing_id = food_claims.listing_id
         AND public.refood_is_user(f.donor_id, 'Donor')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='smart_food_sensors' AND policyname='ReFood signed-in users read sensors') THEN
    CREATE POLICY "ReFood signed-in users read sensors" ON public.smart_food_sensors FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Public directory exposes only donor names, never email or phone.
CREATE OR REPLACE FUNCTION public.refood_public_donors()
RETURNS TABLE(user_id integer, full_name varchar)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT u.user_id, u.full_name FROM public.users u WHERE u.role = 'Donor';
$$;
REVOKE ALL ON FUNCTION public.refood_public_donors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_public_donors() TO authenticated;

-- The aggregate reveals counts and donor names, but no user contact details.
CREATE OR REPLACE FUNCTION public.refood_donor_summary()
RETURNS TABLE(donor_name varchar, listing_count bigint, total_kg numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT u.full_name, count(f.listing_id), coalesce(sum(f.quantity_kg), 0)
  FROM public.food_listings f JOIN public.users u ON u.user_id = f.donor_id
  GROUP BY u.user_id, u.full_name ORDER BY 3 DESC;
$$;
REVOKE ALL ON FUNCTION public.refood_donor_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_donor_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.refood_food_metrics()
RETURNS TABLE(available_count bigint, total_quantity_kg numeric, claim_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT (SELECT count(*) FROM public.food_listings WHERE status='Available' AND expiry_timestamp > now()),
         (SELECT coalesce(sum(quantity_kg),0) FROM public.food_listings),
         (SELECT count(*) FROM public.food_claims);
$$;
REVOKE ALL ON FUNCTION public.refood_food_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_food_metrics() TO authenticated;

REVOKE ALL ON FUNCTION public.refood_sensor_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_sensor_summary() TO authenticated;

-- Booking is one database transaction. A failed update cannot leave an orphan claim.
CREATE OR REPLACE FUNCTION public.refood_book_listing(p_listing_id integer)
RETURNS TABLE(claim_id integer, listing_id integer, listing_status varchar)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_recipient integer; v_claim integer;
BEGIN
  SELECT u.user_id INTO v_recipient FROM public.users u
  WHERE public.refood_is_user(u.user_id, 'Recipient');
  IF v_recipient IS NULL THEN RAISE EXCEPTION 'Sign in as a ReFood recipient'; END IF;
  PERFORM 1 FROM public.food_listings f WHERE f.listing_id=p_listing_id
    AND f.status='Available' AND f.title LIKE 'EXAM TEST %'
    AND f.expiry_timestamp > now() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing is no longer available'; END IF;
  INSERT INTO public.food_claims (listing_id, recipient_id, claim_status)
  VALUES (p_listing_id, v_recipient, 'Pending') RETURNING food_claims.claim_id INTO v_claim;
  UPDATE public.food_listings f SET status='Reserved' WHERE f.listing_id=p_listing_id;
  RETURN QUERY SELECT v_claim, p_listing_id, 'Reserved'::varchar;
END;
$$;
REVOKE ALL ON FUNCTION public.refood_book_listing(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_book_listing(integer) TO authenticated;

-- Block legacy maintenance RPCs for browser roles. They would delete historical
-- telemetry or expire the existing Reserved listing; preserve those rows.
REVOKE ALL ON FUNCTION public.refood_expire_critical_listings() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refood_cleanup_old_sensor_readings() FROM PUBLIC, anon, authenticated;

-- Two explicit demo actions prove INSERT and DELETE of old telemetry without
-- touching any historical sensor row. They require a Donor account and a
-- listing that the same donor created with the EXAM TEST prefix.
CREATE OR REPLACE FUNCTION public.refood_add_old_test_reading(p_listing_id integer)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sensor_id integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.food_listings f
                 WHERE f.listing_id=p_listing_id AND f.title LIKE 'EXAM TEST %'
                   AND public.refood_is_user(f.donor_id, 'Donor')) THEN
    RAISE EXCEPTION 'Use your own EXAM TEST listing';
  END IF;
  INSERT INTO public.smart_food_sensors
    (listing_id, storage_box_id, temperature_celsius, humidity_percent, spoilage_risk, recorded_at)
  VALUES (p_listing_id, 'EXAM-BOX', 4.0, 60, 'Low', now() - interval '7 hours')
  RETURNING sensor_id INTO v_sensor_id;
  RETURN v_sensor_id;
END;
$$;
REVOKE ALL ON FUNCTION public.refood_add_old_test_reading(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_add_old_test_reading(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.refood_cleanup_test_sensor_readings()
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_deleted integer;
BEGIN
  DELETE FROM public.smart_food_sensors s USING public.food_listings f
  WHERE s.listing_id=f.listing_id AND s.storage_box_id = 'EXAM-BOX'
    AND s.recorded_at < now() - interval '6 hours'
    AND f.title LIKE 'EXAM TEST %'
    AND public.refood_is_user(f.donor_id, 'Donor');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
REVOKE ALL ON FUNCTION public.refood_cleanup_test_sensor_readings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_cleanup_test_sensor_readings() TO authenticated;

COMMIT;
