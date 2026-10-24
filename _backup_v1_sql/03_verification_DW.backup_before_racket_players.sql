/* Checks after EL_SRC_SA + ETL_SA_DW : row counts, then the KPIs of the objectives
   (the same calculations will be DAX measures in Power BI) */
USE DW_Padel;

/* 1. row counts - expected values in the comments */
SELECT 'DIM_DATE' AS tbl, COUNT(*) AS n FROM DIM_DATE                 -- 2191 (2021-2026)
UNION ALL SELECT 'DIM_TOURNAMENT', COUNT(*) FROM DIM_TOURNAMENT       -- 168 (157 calendars + 11 of 2025)
UNION ALL SELECT 'DIM_ROUND', COUNT(*) FROM DIM_ROUND                 -- 7
UNION ALL SELECT 'DIM_MATCH_PROFILE', COUNT(*) FROM DIM_MATCH_PROFILE -- 187 distinct scores
UNION ALL SELECT 'DIM_PLAYER', COUNT(*) FROM DIM_PLAYER               -- 4117
UNION ALL SELECT 'DIM_PAIR', COUNT(*) FROM DIM_PAIR                   -- 256 (215 pair names)
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM DIM_PRODUCT             -- 730
UNION ALL SELECT 'FACT_MATCH', COUNT(*) FROM FACT_MATCH               -- 434
UNION ALL SELECT 'FACT_MARKETING', COUNT(*) FROM FACT_MARKETING;      -- 730

/* ---------------- FACT_MATCH ---------------- */
WITH m AS (
    SELECT f.*, p.outcome_code, p.nb_sets, p.nb_tie_breaks,
           CASE WHEN f.winning_pair_key = f.pair1_key THEN ISNULL(f.seed_pair1, 99) ELSE ISNULL(f.seed_pair2, 99) END AS winner_seed,
           CASE WHEN f.winning_pair_key = f.pair1_key THEN ISNULL(f.seed_pair2, 99) ELSE ISNULL(f.seed_pair1, 99) END AS loser_seed
    FROM FACT_MATCH f JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key
)
SELECT
    /* I6 upset rate (1.2) = upsets / eligible matches (99 = not seeded) */
    SUM(CASE WHEN outcome_code <> 'WO' AND loser_seed < winner_seed THEN 1 ELSE 0 END)                    AS upsets,
    SUM(CASE WHEN outcome_code <> 'WO' AND (winner_seed < 99 OR loser_seed < 99) THEN 1 ELSE 0 END)       AS eligible_matches,
    /* I7 3-set rate (1.3) = 3-set matches / normal matches */
    1.0 * SUM(CASE WHEN outcome_code = 'NORMAL' AND nb_sets = 3 THEN 1 ELSE 0 END)
        / SUM(CASE WHEN outcome_code = 'NORMAL' THEN 1 ELSE 0 END)                                         AS three_set_rate,
    /* I12 retirement rate (1.5) = (retirements + walkovers) / matches */
    1.0 * SUM(CASE WHEN outcome_code IN ('RET', 'WO') THEN 1 ELSE 0 END) / COUNT(*)                        AS retirement_rate
FROM m;   -- expected 53 | 287 | 0.271 | 0.021

/* I1 pair win rate (1.1) = wins / matches played, top 10 pairs */
SELECT TOP 10 pr.pair_name,
       SUM(CASE WHEN f.winning_pair_key = pr.pair_key THEN 1 ELSE 0 END) AS wins,
       COUNT(*) AS played,
       1.0 * SUM(CASE WHEN f.winning_pair_key = pr.pair_key THEN 1 ELSE 0 END) / COUNT(*) AS win_rate
FROM FACT_MATCH f
JOIN DIM_PAIR pr ON pr.pair_key IN (f.pair1_key, f.pair2_key)
GROUP BY pr.pair_name
ORDER BY wins DESC;

/* I16 continent share (1.6) = matches in a continent / all matches */
SELECT t.host_continent, COUNT(*) AS matches, 1.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS share
FROM FACT_MATCH f JOIN DIM_TOURNAMENT t ON t.tournament_key = f.tournament_key
GROUP BY t.host_continent;

/* the 11 finals of 2025 */
SELECT t.tournament_name, t.start_date, w.pair_name AS winner, p.score
FROM FACT_MATCH f
JOIN DIM_TOURNAMENT t    ON t.tournament_key = f.tournament_key
JOIN DIM_ROUND r         ON r.round_key = f.round_key
JOIN DIM_PAIR w          ON w.pair_key = f.winning_pair_key
JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key
WHERE r.round_name = 'Final'
ORDER BY t.start_date;

/* ---------------- FACT_MARKETING ---------------- */
/* I19 price gap by brand (2.1) = brand average price - market average */
SELECT d.brand_name, COUNT(*) AS products, AVG(f.price_eur) AS avg_price,
       AVG(f.price_eur) - (SELECT AVG(price_eur) FROM FACT_MARKETING) AS price_gap
FROM FACT_MARKETING f JOIN DIM_PRODUCT d ON d.product_key = f.product_key
GROUP BY d.brand_name ORDER BY avg_price DESC;

/* I20 feature premium (2.2) = average price with the feature - without */
SELECT 'carbon' AS feature,
       AVG(CASE WHEN d.is_carbon = 1 THEN f.price_eur END) - AVG(CASE WHEN d.is_carbon = 0 THEN f.price_eur END) AS premium
FROM FACT_MARKETING f JOIN DIM_PRODUCT d ON d.product_key = f.product_key
UNION ALL
SELECT 'sanded', AVG(CASE WHEN d.is_sanded = 1 THEN f.price_eur END) - AVG(CASE WHEN d.is_sanded = 0 THEN f.price_eur END)
FROM FACT_MARKETING f JOIN DIM_PRODUCT d ON d.product_key = f.product_key
UNION ALL
SELECT 'pro model', AVG(CASE WHEN d.is_pro_racket = 1 THEN f.price_eur END) - AVG(CASE WHEN d.is_pro_racket = 0 THEN f.price_eur END)
FROM FACT_MARKETING f JOIN DIM_PRODUCT d ON d.product_key = f.product_key;

/* I21 commercial value (2.3) = average price of the player's rackets */
SELECT pl.player_name, pl.ranking_position, COUNT(*) AS rackets, AVG(f.price_eur) AS avg_price
FROM FACT_MARKETING f JOIN DIM_PLAYER pl ON pl.player_key = f.player_key
GROUP BY pl.player_name, pl.ranking_position;   -- expected: Agustin Tapia, 18 rackets
