-- The five SQL operations from the exam brief, kept as written.
-- Queries 1–3 are read-only and safe to run as they are.
-- Queries 4 and 5 CHANGE or DELETE historical data, so each one comes with:
--   (a) a read-only PREVIEW showing exactly which rows would be affected, and
--   (b) the original statement inside a transaction that ends with ROLLBACK (nothing is saved).
-- Run ONE block at a time in Supabase → SQL Editor. Do not remove ROLLBACK unless the owner approves.

-- ============ 1. Filtering available food (SELECT + WHERE) ============
SELECT listing_id, title, category, quantity_kg
FROM food_listings
WHERE status = 'Available';

-- ============ 2. Aggregation: food per donor (JOIN + COUNT + SUM + GROUP BY) ============
SELECT u.full_name AS donor,
       COUNT(f.listing_id) AS listings,
       SUM(f.quantity_kg) AS total_kg
FROM food_listings f
JOIN users u ON f.donor_id = u.user_id
GROUP BY u.full_name
ORDER BY total_kg DESC;

-- ============ 3. Smart sensor aggregation (AVG + MAX + COUNT + GROUP BY) ============
SELECT storage_box_id,
       ROUND(AVG(temperature_celsius), 1) AS avg_temp,
       MAX(temperature_celsius) AS max_temp,
       COUNT(*) AS readings
FROM smart_food_sensors
GROUP BY storage_box_id
ORDER BY avg_temp DESC;

-- ============ 4. UPDATE: expire listings that have a Critical sensor reading ============
-- 4a. PREVIEW (read-only): which listings would become 'Expired'?
SELECT f.listing_id, f.title, f.status AS current_status
FROM food_listings f
WHERE f.listing_id IN (SELECT listing_id FROM smart_food_sensors WHERE spoilage_risk = 'Critical');

-- 4b. Original statement, executed and then UNDONE with ROLLBACK (shows the effect, saves nothing).
BEGIN;
  UPDATE food_listings
  SET status = 'Expired'
  WHERE listing_id IN (SELECT listing_id FROM smart_food_sensors WHERE spoilage_risk = 'Critical');

  SELECT listing_id, title, status          -- the exam asked for listing_id = 2; this shows all affected rows
  FROM food_listings
  WHERE listing_id IN (SELECT listing_id FROM smart_food_sensors WHERE spoilage_risk = 'Critical');
ROLLBACK;

-- ============ 5. DELETE: remove sensor readings older than six hours ============
-- 5a. PREVIEW (read-only): how many rows would go, how many would remain?
SELECT COUNT(*) FILTER (WHERE recorded_at <  NOW() - INTERVAL '6 hours') AS would_be_deleted,
       COUNT(*) FILTER (WHERE recorded_at >= NOW() - INTERVAL '6 hours') AS would_remain,
       COUNT(*) AS total_now
FROM smart_food_sensors;

-- 5b. Original statement, executed and then UNDONE with ROLLBACK.
BEGIN;
  DELETE FROM smart_food_sensors
  WHERE recorded_at < NOW() - INTERVAL '6 hours';

  SELECT COUNT(*) AS remaining_readings FROM smart_food_sensors;   -- value inside the transaction
ROLLBACK;
SELECT COUNT(*) AS readings_after_rollback FROM smart_food_sensors;  -- back to the original number
