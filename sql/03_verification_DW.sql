/* Checks after EL_SRC_SA + ETL_SA_DW : row counts and the KPIs of the data marts */
USE DW_Padel;
SELECT 'DIM_DATE' AS chk, COUNT(*) AS n FROM DIM_DATE UNION ALL SELECT 'DIM_ROUND', COUNT(*) FROM DIM_ROUND
UNION ALL SELECT 'DIM_MATCH_PROFILE', COUNT(*) FROM DIM_MATCH_PROFILE UNION ALL SELECT 'DIM_TOURNAMENT', COUNT(*) FROM DIM_TOURNAMENT
UNION ALL SELECT 'DIM_PLAYER', COUNT(*) FROM DIM_PLAYER UNION ALL SELECT 'DIM_PAIR', COUNT(*) FROM DIM_PAIR
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM DIM_PRODUCT UNION ALL SELECT 'FACT_MATCH', COUNT(*) FROM FACT_MATCH
UNION ALL SELECT 'FACT_MARKETING', COUNT(*) FROM FACT_MARKETING
UNION ALL SELECT 'KPI upsets', SUM(nb_upsets) FROM FACT_MATCH
UNION ALL SELECT 'KPI eligible matches', SUM(nb_eligible_matches) FROM FACT_MATCH
UNION ALL SELECT 'NORMAL matches', COUNT(*) FROM FACT_MATCH f JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key WHERE p.outcome_code = 'NORMAL'
UNION ALL SELECT 'KPI 3 sets x1000 (NORMAL)', 1000 * SUM(CASE WHEN f.nb_sets = 3 THEN 1 ELSE 0 END) / COUNT(*) FROM FACT_MATCH f JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key WHERE p.outcome_code = 'NORMAL'
UNION ALL SELECT 'KPI tie-break x1000 (NORMAL)', 1000 * SUM(CASE WHEN f.nb_tie_breaks > 0 THEN 1 ELSE 0 END) / COUNT(*) FROM FACT_MATCH f JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key WHERE p.outcome_code = 'NORMAL'
UNION ALL SELECT 'KPI game gap x100 (NORMAL)', 100 * SUM(CAST(f.games_winner AS int) - f.games_loser) / COUNT(*) FROM FACT_MATCH f JOIN DIM_MATCH_PROFILE p ON p.profile_key = f.profile_key WHERE p.outcome_code = 'NORMAL'
UNION ALL SELECT 'matches without points pair1', SUM(CASE WHEN points_pair1 IS NULL THEN 1 ELSE 0 END) FROM FACT_MATCH
UNION ALL SELECT 'tournaments without country', SUM(CASE WHEN host_country_code IS NULL THEN 1 ELSE 0 END) FROM DIM_TOURNAMENT
UNION ALL SELECT 'signature rackets', SUM(CAST(is_pro_racket AS int)) FROM DIM_PRODUCT
UNION ALL SELECT 'rackets linked to a player', COUNT(*) FROM FACT_MARKETING WHERE player_key <> -1;

/* the finals of 2025 */
SELECT t.tournament_name, t.city, t.host_country_code, t.host_continent, w.pair_name AS winner,
       f.nb_sets, f.games_winner, f.games_loser, f.points_pair1, f.points_pair2
FROM FACT_MATCH f
JOIN DIM_TOURNAMENT t ON t.tournament_key = f.tournament_key
JOIN DIM_ROUND r      ON r.round_key = f.round_key
JOIN DIM_PAIR w       ON w.pair_key = f.winning_pair_key
WHERE r.code = 'F'
ORDER BY f.date_key;
