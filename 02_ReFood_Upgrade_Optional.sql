-- ReFood — OPTIONAL upgrade (v2). Additive only: three new functions, no table or column is touched.
-- Run ONCE in Supabase → SQL Editor, AFTER 01_ReFood_Safe_Demo_Setup.sql.
-- The website works without it; without it the new buttons (Approve / Reject / Cancel) and the
-- "Food rescued" tile simply show a hint that this file has not been run.
--
-- Logic tested on a local PostgreSQL 16 copy of your schema (book → cancel → approve → reject, plus permission
-- failures for the wrong role and for anon). NOT yet run on your real Supabase project — run the test steps at the bottom.
-- Like the rest of the demo, these functions only touch listings whose title starts with 'EXAM TEST '.
-- (Remove that LIKE condition later if you want the app to manage real listings.)

BEGIN;

-- Donor approves or rejects a Pending claim on their own listing (UPDATE claim; Rejected frees the listing).
CREATE OR REPLACE FUNCTION public.refood_review_claim(p_claim_id integer, p_decision text)
RETURNS TABLE(out_claim_id integer, out_claim_status varchar, out_listing_id integer, out_listing_status varchar)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_listing integer;
BEGIN
  IF p_decision NOT IN ('Approved', 'Rejected') THEN
    RAISE EXCEPTION 'Decision must be Approved or Rejected';
  END IF;

  SELECT c.listing_id INTO v_listing
  FROM public.food_claims c
  JOIN public.food_listings f ON f.listing_id = c.listing_id
  WHERE c.claim_id = p_claim_id
    AND c.claim_status = 'Pending'
    AND f.title LIKE 'EXAM TEST %'
    AND public.refood_is_user(f.donor_id, 'Donor')
  FOR UPDATE OF c;

  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Pending claim on your own EXAM TEST listing not found';
  END IF;

  UPDATE public.food_claims SET claim_status = p_decision WHERE claim_id = p_claim_id;

  IF p_decision = 'Rejected' THEN
    UPDATE public.food_listings SET status = 'Available'
    WHERE listing_id = v_listing AND status = 'Reserved';
  END IF;

  RETURN QUERY
    SELECT p_claim_id, p_decision::varchar, v_listing,
           (SELECT f.status FROM public.food_listings f WHERE f.listing_id = v_listing)::varchar;
END;
$$;
REVOKE ALL ON FUNCTION public.refood_review_claim(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_review_claim(integer, text) TO authenticated;

-- Recipient cancels their own Pending claim (DELETE claim + listing becomes Available again).
CREATE OR REPLACE FUNCTION public.refood_cancel_claim(p_claim_id integer)
RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_listing integer;
BEGIN
  SELECT c.listing_id INTO v_listing
  FROM public.food_claims c
  JOIN public.food_listings f ON f.listing_id = c.listing_id
  WHERE c.claim_id = p_claim_id
    AND c.claim_status = 'Pending'
    AND f.title LIKE 'EXAM TEST %'
    AND public.refood_is_user(c.recipient_id, 'Recipient')
  FOR UPDATE OF c;

  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Your own Pending claim on an EXAM TEST listing was not found';
  END IF;

  DELETE FROM public.food_claims WHERE claim_id = p_claim_id;
  UPDATE public.food_listings SET status = 'Available'
  WHERE listing_id = v_listing AND status = 'Reserved';
  RETURN v_listing;
END;
$$;
REVOKE ALL ON FUNCTION public.refood_cancel_claim(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_cancel_claim(integer) TO authenticated;

-- "Food rescued": total kg of listings whose claim was Approved (aggregation: SUM + COUNT with FILTER).
CREATE OR REPLACE FUNCTION public.refood_impact()
RETURNS TABLE(rescued_kg numeric, approved_claims bigint, pending_claims bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(SUM(f.quantity_kg) FILTER (WHERE c.claim_status = 'Approved'), 0),
         COUNT(*) FILTER (WHERE c.claim_status = 'Approved'),
         COUNT(*) FILTER (WHERE c.claim_status = 'Pending')
  FROM public.food_claims c
  JOIN public.food_listings f ON f.listing_id = c.listing_id;
$$;
REVOKE ALL ON FUNCTION public.refood_impact() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refood_impact() TO authenticated;

COMMIT;

-- ---------------------------------------------------------------------------------------------
-- HOW TO TEST (in the website, after running this file):
--  1. Sign in as Recipient → reserve a NEW EXAM TEST listing → Claims tab shows it as Pending.
--  2. Press "Cancel" → the claim disappears and the listing is Available again.   (DELETE + UPDATE)
--  3. Reserve it again. Sign out, sign in as Donor → Claims tab → "Approve".       (UPDATE)
--  4. The "Food rescued" tile now shows the listing's kg.                          (SUM)
--  Do NOT cancel claim #5 / listing #6 — they are your evidence for the exam.
--
-- UNDO (removes only the three functions):
--   DROP FUNCTION IF EXISTS public.refood_review_claim(integer, text);
--   DROP FUNCTION IF EXISTS public.refood_cancel_claim(integer);
--   DROP FUNCTION IF EXISTS public.refood_impact();
