-- ReFood defense: SELECT only. Run one query at a time in Supabase → SQL Editor.
-- No fixed IDs: every query follows whatever is in the database at that moment.

-- A. EXAM TEST listings (the live demo data).
SELECT listing_id, title, category, quantity_kg, status, expiry_timestamp
FROM public.food_listings
WHERE title LIKE 'EXAM TEST %'
ORDER BY listing_id DESC;

-- B. A booking touches two linked tables: the claim row and the listing status.
SELECT f.listing_id, f.title, f.status AS listing_status,
       c.claim_id, c.recipient_id, c.claim_status, c.claim_timestamp
FROM public.food_listings AS f
JOIN public.food_claims  AS c ON c.listing_id = f.listing_id
WHERE f.title LIKE 'EXAM TEST %'
ORDER BY c.claim_id DESC;

-- C. Listings and kg per donor (JOIN + COUNT + SUM + GROUP BY).
SELECT u.user_id, u.full_name, COUNT(f.listing_id) AS listing_count,
       COALESCE(SUM(f.quantity_kg), 0) AS total_kg
FROM public.users AS u
LEFT JOIN public.food_listings AS f ON f.donor_id = u.user_id
WHERE u.role = 'Donor'
GROUP BY u.user_id, u.full_name
ORDER BY total_kg DESC;

-- D. Sensor analysis per storage box (AVG + MAX + COUNT + GROUP BY).
SELECT storage_box_id, COUNT(*) AS readings,
       ROUND(AVG(temperature_celsius), 1) AS avg_temp,
       MAX(temperature_celsius) AS max_temp
FROM public.smart_food_sensors
GROUP BY storage_box_id
ORDER BY avg_temp DESC;

-- E. Proof that deleting a test reading left the original data alone.
SELECT COUNT(*) AS total_readings,
       COUNT(*) FILTER (WHERE storage_box_id = 'EXAM-BOX') AS exam_box_readings
FROM public.smart_food_sensors;

-- F. Row-level security is on, and these are the policies the app relies on.
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- G. Foreign keys that connect the five tables (shown for the HCI→SQL slide).
SELECT conrelid::regclass AS child_table, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'public'::regnamespace
ORDER BY 1, 2;
