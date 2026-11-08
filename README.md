# ReFood Astana

Surplus-food exchange for Astana, Kazakhstan — a university final-exam project (ST-2607).
Donors publish surplus food, recipients filter and reserve it, and smart sensors monitor storage.
Every list, number and button is backed by a real **Supabase** (PostgreSQL) database — no mock data.

**Live site:** `https://<your-github-username>.github.io/<repository-name>/`

## What is inside

| Path | Purpose |
|---|---|
| `index.html` | The whole web app (HTML + CSS + JavaScript, one file) |
| `sql/01_ReFood_Safe_Demo_Setup.sql` | Row Level Security + booking / demo functions (already applied to the project) |
| `sql/02_ReFood_Upgrade_Optional.sql` | Optional: approve / reject / cancel claims and the “Food rescued” tile |
| `sql/03_ReFood_Exam_Queries_Official.sql` | The five exam queries, with safe previews and ROLLBACK |
| `sql/04_ReFood_Defense_Read_Only.sql` | SELECT-only checks for the live defense |

## Features
* Sign in with Supabase Auth as **Donor** or **Recipient**.
* `SELECT … WHERE` filters (category, district, status) and live metrics.
* Aggregation: `COUNT`, `SUM`, `AVG`, `MAX`, `GROUP BY` (donor impact, smart storage).
* `INSERT` (pickup location, listing, test sensor reading), `UPDATE` (listing status, booking), `DELETE` (own test records).
* A **SQL trace** panel shows the query and the real response for every action.

## Security notes
* The page contains only the project URL and the **publishable (anon) key**. Never commit a `service_role` key or a password.
* Access is enforced in the database by Row Level Security and `SECURITY DEFINER` functions.
* Demo writes are limited to listings whose title starts with `EXAM TEST `.

## Run locally
Open `index.html` in a browser, or run `python3 -m http.server 3000` in this folder and visit http://127.0.0.1:3000/.
