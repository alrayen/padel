/* =====================================================================
   SA_Padel : transformation views read by the package ETL_SA_DW
   (the staging tables stay raw; all cleaning rules live here, in one place)

   vw_Match_Joueurs   one row per player slot of a match (4 per match)
   vw_Match_Paires    one row per pair of a match (2 per match)
   vw_Matchs          one row per match, cleaned and coded
   vw_Produits        one row per product + signature player detected
   vw_Dim_*           one view per dimension (columns = DW types + row_hash)
   vw_Fact_*          one view per fact table (business codes, measures)
   ===================================================================== */
USE SA_Padel;
GO

/* ---------------------------------------------------------------------
   fn_norm : upper case, no accents, single spaces
   "GOÑI LACABE, Aimar" and "Aimar Goñi Lacabe" give the same letters
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_norm (@s NVARCHAR(400))
RETURNS NVARCHAR(400)
WITH SCHEMABINDING
AS
BEGIN
    -- one single expression (no loop) so that SQL Server can inline it in the views
    RETURN UPPER(LTRIM(RTRIM(
             REPLACE(REPLACE(REPLACE(
               TRANSLATE(REPLACE(REPLACE(@s, N'æ', N'ae'), N'Æ', N'AE') COLLATE Latin1_General_100_CS_AS,
                 N'ÁÀÂÄÃÅáàâäãåÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕØóòôöõøÚÙÛÜúùûüÑñÇçŠšŽžÝýÿ',
                 N'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuNnCcSsZzYyy'),
             N'  ', N' '), N'  ', N' '), N'  ', N' '))));
END
GO

/* ---------------------------------------------------------------------
   Players of the matches.  player_code = gender | FIRST LAST (no accents)
   = the same code as in the ranking files.  The professor's 11 files are
   the men's main draws, so gender = 'M'.
   12 players are spelled differently in the draws and in the ranking :
   alias list below (checked by hand against men-Players.csv).
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Match_Joueurs AS
WITH slots AS (
    SELECT m.match_id, v.slot, v.name, v.country
    FROM dbo.Matchs_SA m
    CROSS APPLY (VALUES (N'p1j1', m.pair1_player1, m.pair1_country1),
                        (N'p1j2', m.pair1_player2, m.pair1_country2),
                        (N'p2j1', m.pair2_player1, m.pair2_country1),
                        (N'p2j2', m.pair2_player2, m.pair2_country2)) v(slot, name, country)
),
alias AS (
    SELECT dbo.fn_norm(a) AS draw_name, dbo.fn_norm(r) AS ranking_name
    FROM (VALUES (N'MOYA SOS, Jesús',               N'Jesus Moya'),
                 (N'NIETO RUIZ, Jorge',             N'Jorge Nieto'),
                 (N'RUIZ GRANADOS, Alejandro',      N'Alejandro Ruiz'),
                 (N'AYATS DELGADO, Arnau',          N'Arnau Ayats'),
                 (N'ABDULLA, Rayan',                N'Rayan Abdulla Aljufairi'),
                 (N'GIL MORALES, Francisco Manuel', N'Francisco Manuel Gil'),
                 (N'TORRE, Agustín',                N'Eduardo Agustin Torre'),
                 (N'RUIZ GONZALEZ, Javier',         N'Javier Ruiz'),
                 (N'SANCHEZ AGUERO, Maximiliano',   N'Maximiliano Sanchez'),
                 (N'ROMAN AUGSBURGUER, Leandro',    N'Leandro Augsburger'),
                 (N'GALA, David',                   N'David Gala Sanchez')) x(a, r)
),
split AS (
    SELECT s.match_id, s.slot, s.name, NULLIF(LTRIM(RTRIM(s.country)), N'') AS country_code,
           LTRIM(RTRIM(LEFT(s.name, CHARINDEX(N',', s.name + N',') - 1)))           AS last_part,
           LTRIM(RTRIM(SUBSTRING(s.name, CHARINDEX(N',', s.name + N',') + 1, 200))) AS first_part
    FROM slots s
)
SELECT sp.match_id, sp.slot, sp.name, sp.country_code,
       UPPER(sp.last_part) AS last_name,
       sp.first_part       AS first_name,
       N'M|' + COALESCE(al.ranking_name, dbo.fn_norm(sp.first_part + N' ' + sp.last_part)) AS player_code
FROM split sp
LEFT JOIN alias al ON al.draw_name = dbo.fn_norm(sp.name);
GO

/* ---------------------------------------------------------------------
   Player codes are computed ONCE and stored (fn_norm inside joins is slow):
   procedure sp_preparer_codes, called by the first task of ETL_SA_DW.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.Joueurs_Match_Codes;
DROP TABLE IF EXISTS dbo.Classement_Codes;
GO
CREATE TABLE dbo.Joueurs_Match_Codes (          -- one row per player slot of a match
    match_id      INT           NOT NULL,
    slot          NVARCHAR(4)   NOT NULL,       -- p1j1, p1j2, p2j1, p2j2
    name          NVARCHAR(150) NULL,
    country_code  NVARCHAR(10)  NULL,
    last_name     NVARCHAR(150) NULL,
    first_name    NVARCHAR(150) NULL,
    player_code   NVARCHAR(150) NOT NULL,
    CONSTRAINT PK_Joueurs_Match_Codes PRIMARY KEY (match_id, slot)
);
CREATE INDEX IX_Joueurs_Match_Codes_code ON dbo.Joueurs_Match_Codes (player_code);

CREATE TABLE dbo.Classement_Codes (             -- one row per ranked player
    player_code      NVARCHAR(150) NOT NULL,
    name             NVARCHAR(150) NULL,
    gender           NCHAR(1)      NULL,
    country_code     NVARCHAR(10)  NULL,
    ranking_position INT           NULL,
    ranking_points   INT           NULL
);
CREATE CLUSTERED INDEX IX_Classement_Codes_code ON dbo.Classement_Codes (player_code);
GO

CREATE OR ALTER PROCEDURE dbo.sp_preparer_codes
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE dbo.Joueurs_Match_Codes;
    INSERT INTO dbo.Joueurs_Match_Codes (match_id, slot, name, country_code, last_name, first_name, player_code)
    SELECT match_id, slot, name, country_code, last_name, first_name, player_code
    FROM dbo.vw_Match_Joueurs;

    TRUNCATE TABLE dbo.Classement_Codes;
    INSERT INTO dbo.Classement_Codes (player_code, name, gender, country_code, ranking_position, ranking_points)
    SELECT j.gender + N'|' + dbo.fn_norm(j.name), LTRIM(RTRIM(j.name)), j.gender,
           NULLIF(LTRIM(j.country), N''), TRY_CONVERT(int, j.position), TRY_CONVERT(int, j.points)
    FROM dbo.Joueurs_SA j;
END
GO

/* one row per pair and per match ; the two codes are put in alphabetical
   order so that COELLO/TAPIA and TAPIA/COELLO are the same pair          */
CREATE OR ALTER VIEW dbo.vw_Match_Paires AS
SELECT j1.match_id,
       LEFT(j1.slot, 2) AS side,                                  -- p1 / p2
       CASE WHEN j1.player_code <= j2.player_code THEN j1.player_code ELSE j2.player_code END AS player1_code,
       CASE WHEN j1.player_code <= j2.player_code THEN j2.player_code ELSE j1.player_code END AS player2_code
FROM dbo.Joueurs_Match_Codes j1
JOIN dbo.Joueurs_Match_Codes j2 ON j2.match_id = j1.match_id AND j2.slot = LEFT(j1.slot, 2) + N'j2'
WHERE j1.slot IN (N'p1j1', N'p2j1');
GO

/* ---------------------------------------------------------------------
   vw_Matchs : one cleaned row per match
   - date in the file = first day of the tournament (Finals 2025 : 11/12)
   - match_number = order of the match inside its tournament file
   - outcome : WO (walkover), RET (retirement), NORMAL
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Matchs AS
SELECT m.match_id,
       CAST(ROW_NUMBER() OVER (PARTITION BY m.tournament, m.[date] ORDER BY m.match_id) AS int) AS match_number,
       m.tournament                                            AS tournament_name,
       COALESCE(TRY_CONVERT(date, m.[date]), CAST('19000101' AS date)) AS full_date,
       dbo.fn_norm(m.tournament) + N'|' + LEFT(m.[date], 4)    AS tournament_code,
       CASE m.[round] WHEN N'Round of 64'   THEN N'R64' WHEN N'Round of 32' THEN N'R32'
                      WHEN N'Round of 16'   THEN N'R16' WHEN N'Quarterfinals' THEN N'QF'
                      WHEN N'Semifinals'    THEN N'SF'  WHEN N'3rd Place'   THEN N'3P'
                      WHEN N'Final'         THEN N'F'   ELSE LEFT(m.[round], 50) END AS round_code,
       CASE m.[round] WHEN N'Round of 64'   THEN 1 WHEN N'Round of 32' THEN 2
                      WHEN N'Round of 16'   THEN 3 WHEN N'Quarterfinals' THEN 4
                      WHEN N'Semifinals'    THEN 5 WHEN N'3rd Place'   THEN 6
                      WHEN N'Final'         THEN 7 ELSE 99 END             AS round_sort,
       CASE WHEN m.score = N'WO' THEN N'WO' WHEN m.score LIKE N'%RET%' THEN N'RET' ELSE N'NORMAL' END AS outcome_code,
       CASE WHEN NULLIF(LTRIM(m.pair1_seed), N'') IS NULL THEN N'UNSEEDED' ELSE N'SEEDED' END AS pair1_status,
       CASE WHEN NULLIF(LTRIM(m.pair2_seed), N'') IS NULL THEN N'UNSEEDED' ELSE N'SEEDED' END AS pair2_status,
       TRY_CONVERT(tinyint, NULLIF(LTRIM(m.pair1_seed), N'')) AS seed_pair1,
       TRY_CONVERT(tinyint, NULLIF(LTRIM(m.pair2_seed), N'')) AS seed_pair2,
       m.winner,
       m.score
FROM dbo.Matchs_SA m;
GO

/* ---------------------------------------------------------------------
   Products + signature player.  A "signature" racket carries a pro
   player's name or model line in its title (Head Coello, Nox AT10 = Tapia,
   Siux Stupa...).  player_code NULL = signature of a retired player (Bela)
   or ambiguous name (Javi Ruiz) -> no player link.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Produits AS
WITH sig AS (
    SELECT * FROM (VALUES
        (N'COELLO',      N'M|ARTURO COELLO'),
        (N'LEBRON',      N'M|JUAN LEBRON'),
        (N'TAPIA',       N'M|AGUSTIN TAPIA'),
        (N'AT10',        N'M|AGUSTIN TAPIA'),
        (N'AUGSBURGER',  N'M|LEANDRO AUGSBURGER'),
        (N'LA10',        N'M|LEANDRO AUGSBURGER'),
        (N'STUPA',       N'M|FRANCO STUPACZUK'),
        (N'CHOZAS',      N'M|ALEX CHOZAS'),
        (N'LAMPERTI',    N'M|MIGUEL LAMPERTI'),
        (N'LIBAAK',      N'M|VALENTINO GABRIEL LIBAAK'),
        (N'ARAUJO',      N'F|SOFIA ARAUJO'),
        (N'OSORO',       N'F|ARANZAZU OSORO ULRICH'),
        (N'ARI SANCHEZ', N'F|ARIANA SANCHEZ FALLADA'),
        (N'BELA',        NULL),
        (N'JAVI RUIZ',   NULL)) v(keyword, player_code)
)
SELECT p.*,
       s.keyword AS signature_keyword,
       COALESCE(s.player_code, CASE WHEN p.professional_player = N'tapia' THEN N'M|AGUSTIN TAPIA' END) AS signature_player_code
FROM dbo.Produits_SA p
OUTER APPLY (SELECT TOP 1 sig.keyword, sig.player_code
             FROM sig
             WHERE N' ' + dbo.fn_norm(REPLACE(REPLACE(p.title, N'-', N' '), N'.', N' ')) + N' ' LIKE N'% ' + sig.keyword + N' %'
             ORDER BY CASE WHEN sig.player_code IS NULL THEN 1 ELSE 0 END, LEN(sig.keyword) DESC) s;
GO

/* =====================================================================
   DIMENSIONS  (each column cast to the exact DW type ; row_hash = CHECKSUM
   of the attributes, compared with the same CHECKSUM computed on the DW
   side to find the rows that changed)
   ===================================================================== */

-- DIM_ROUND
CREATE OR ALTER VIEW dbo.vw_Dim_Round AS
SELECT DISTINCT
       CAST(round_code AS nvarchar(50)) AS code,
       CAST(round_sort AS tinyint)      AS sort_order,
       CHECKSUM(CAST(round_sort AS tinyint)) AS row_hash
FROM dbo.vw_Matchs;
GO

-- DIM_MATCH_PROFILE (junk dimension : outcome + seeded status of each pair)
CREATE OR ALTER VIEW dbo.vw_Dim_Match_Profile AS
SELECT DISTINCT
       CAST(outcome_code + N'|' + pair1_status + N'|' + pair2_status AS nvarchar(40)) AS profile_code,
       CAST(outcome_code AS nvarchar(10)) AS outcome_code,
       CAST(pair1_status AS nvarchar(10)) AS pair1_status,
       CAST(pair2_status AS nvarchar(10)) AS pair2_status,
       CHECKSUM(CAST(outcome_code AS nvarchar(10)), CAST(pair1_status AS nvarchar(10)), CAST(pair2_status AS nvarchar(10))) AS row_hash
FROM dbo.vw_Matchs;
GO

/* DIM_TOURNAMENT : calendars 2023 / 2024 / 2026 + the 11 tournaments of 2025
   (no 2025 calendar among the professor's files -> built from the matches).
   Host city / country : the calendar country when given, otherwise a place
   keyword found in the name (2023 calendar and 2025 files have no country). */
CREATE OR ALTER VIEW dbo.vw_Dim_Tournament AS
WITH src AS (
    SELECT c.tournament                         AS tournament_name,
           NULLIF(LTRIM(c.category), N'')       AS category,
           NULLIF(LTRIM(c.country), N'')        AS country_name,
           TRY_CONVERT(date, c.start_date)      AS start_date,
           TRY_CONVERT(date, c.end_date)        AS end_date
    FROM dbo.Calendrier_SA c
    UNION ALL
    SELECT DISTINCT m.tournament,
           CASE WHEN m.tournament LIKE N'%MAJOR%'  THEN N'Premier Padel Major'
                WHEN m.tournament LIKE N'%FINALS%' THEN N'Premier Padel Finals'
                WHEN m.tournament LIKE N'% P1'     THEN N'Premier Padel P1'
                WHEN m.tournament LIKE N'% P2'     THEN N'Premier Padel P2' END,
           NULL,
           TRY_CONVERT(date, m.[date]),
           NULL
    FROM dbo.Matchs_SA m
),
place AS (
    SELECT * FROM (VALUES
        (N'RIYADH', N'Riyadh', N'KSA'),           (N'QATAR', N'Doha', N'QAT'),
        (N'ITALY MAJOR', N'Rome', N'ITA'),        (N'MADRID', N'Madrid', N'ESP'),
        (N'MENDOZA', N'Mendoza', N'ARG'),         (N'PARIS', N'Paris', N'FRA'),
        (N'NEW GIZA', N'New Giza', N'EGY'),       (N'NEWGIZA', N'New Giza', N'EGY'),
        (N'MEXICO MAJOR', NULL, N'MEX'),          (N'MILANO', N'Milan', N'ITA'),
        (N'ACAPULCO', N'Acapulco', N'MEX'),       (N'PUERTO CABELLO', N'Puerto Cabello', N'VEN'),
        (N'BRUSSELS', N'Brussels', N'BEL'),       (N'SEVILLA', N'Seville', N'ESP'),
        (N'ASUNCION', N'Asuncion', N'PAR'),       (N'MAR DEL PLATA', N'Mar del Plata', N'ARG'),
        (N'SANTIAGO', N'Santiago', N'CHI'),       (N'BORDEAUX', N'Bordeaux', N'FRA'),
        (N'GENOVA', N'Genoa', N'ITA'),            (N'MALAGA', N'Malaga', N'ESP'),
        (N'FINLAND', NULL, N'FIN'),               (N'ROTTERDAM', N'Rotterdam', N'NED'),
        (N'VALLADOLID', N'Valladolid', N'ESP'),   (N'DUBAI', N'Dubai', N'UAE'),
        (N'KUWAIT', N'Kuwait City', N'KUW'),      (N'BARCELONA', N'Barcelona', N'ESP'),
        (N'PREMIER PADEL FINALS', N'Barcelona', N'ESP'),   -- 2025 Finals : Palau Sant Jordi, 11-14 Dec 2025
        (N'GIJON', N'Gijon', N'ESP'),             (N'CANCUN', N'Cancun', N'MEX'),
        (N'MIAMI', N'Miami', N'USA'),             (N'BUENOS AIRES', N'Buenos Aires', N'ARG'),
        (N'VALENCIA', N'Valencia', N'ESP'),       (N'PRETORIA', N'Pretoria', N'RSA'),
        (N'LONDON', N'London', N'GBR'),           (N'GERMANY', NULL, N'GER')) v(keyword, city, country_code)
),
t AS (
    SELECT s.*, dbo.fn_norm(s.tournament_name) AS name_norm,
           pc.country_code AS cal_country_code,
           pl.city, pl.country_code AS kw_country_code
    FROM src s
    LEFT JOIN dbo.Pays_SA pc ON pc.country_name = s.country_name
    OUTER APPLY (SELECT TOP 1 p.city, p.country_code FROM place p
                 WHERE N' ' + dbo.fn_norm(s.tournament_name) + N' ' LIKE N'% ' + p.keyword + N' %'
                 ORDER BY LEN(p.keyword) DESC) pl
),
f AS (
    SELECT CAST(t.name_norm + N'|' + CAST(YEAR(t.start_date) AS nvarchar(4)) AS nvarchar(160)) AS tournament_code,
           CAST(t.tournament_name AS nvarchar(150))                          AS tournament_name,
           CAST(t.category AS nvarchar(100))                                 AS category,
           CAST(t.city AS nvarchar(100))                                     AS city,
           CAST(COALESCE(t.cal_country_code, t.kw_country_code) AS nvarchar(10)) AS host_country_code,
           CAST(pa.continent AS nvarchar(50))                                AS host_continent,
           CAST(YEAR(t.start_date) AS smallint)                              AS [year],
           t.start_date,
           t.end_date
    FROM t
    LEFT JOIN dbo.Pays_SA pa ON pa.country_code = COALESCE(t.cal_country_code, t.kw_country_code)
)
SELECT f.*,
       CHECKSUM(tournament_name, category, city, host_country_code, host_continent, [year], start_date, end_date) AS row_hash
FROM f;
GO

/* DIM_PLAYER : the 4,117 ranked players (men + women, ranking of January 2026)
   + the players of the matches who are not in the ranking (Salva ORIA).
   Names : "LAST, First" spelling of the draws when the player played,
   otherwise first word = first name, rest = last name.                    */
CREATE OR ALTER VIEW dbo.vw_Dim_Player AS
WITH rk AS (
    SELECT player_code, name, gender, country_code, ranking_position, ranking_points
    FROM dbo.Classement_Codes
),
mj AS (
    SELECT player_code, last_name, first_name, country_code,
           ROW_NUMBER() OVER (PARTITION BY player_code ORDER BY COUNT(*) DESC, last_name, first_name) AS rn
    FROM dbo.Joueurs_Match_Codes
    GROUP BY player_code, last_name, first_name, country_code
),
p AS (
    SELECT rk.player_code,
           COALESCE(mj.last_name,
                    NULLIF(UPPER(LTRIM(SUBSTRING(rk.name, CHARINDEX(N' ', rk.name + N' ') + 1, 200))), N''),
                    UPPER(rk.name))                                        AS last_name,
           COALESCE(mj.first_name, LEFT(rk.name, CHARINDEX(N' ', rk.name + N' ') - 1)) AS first_name,
           rk.gender,
           COALESCE(rk.country_code, mj.country_code)                      AS country_code,
           rk.ranking_position,
           rk.ranking_points
    FROM rk
    LEFT JOIN mj ON mj.player_code = rk.player_code AND mj.rn = 1
    UNION ALL
    SELECT mj.player_code, mj.last_name, mj.first_name, N'M', mj.country_code, NULL, NULL
    FROM mj
    WHERE mj.rn = 1 AND NOT EXISTS (SELECT 1 FROM rk WHERE rk.player_code = mj.player_code)
),
f AS (
    SELECT CAST(p.player_code AS nvarchar(150))  AS player_code,
           CAST(p.last_name AS nvarchar(100))    AS last_name,
           CAST(p.first_name AS nvarchar(100))   AS first_name,
           CAST(p.gender AS nchar(1))            AS gender,
           CAST(p.country_code AS nvarchar(10))  AS country_code,
           CAST(pa.continent AS nvarchar(50))    AS continent,
           p.ranking_position,
           p.ranking_points
    FROM p
    LEFT JOIN dbo.Pays_SA pa ON pa.country_code = p.country_code
)
SELECT f.*,
       CHECKSUM(last_name, first_name, gender, country_code, continent, ranking_position, ranking_points) AS row_hash
FROM f;
GO

-- DIM_PAIR (snowflake : the two players are found in DIM_PLAYER by SSIS)
CREATE OR ALTER VIEW dbo.vw_Dim_Pair AS
WITH pr AS (
    SELECT DISTINCT player1_code, player2_code FROM dbo.vw_Match_Paires
),
f AS (
    SELECT CAST(pr.player1_code + N' + ' + pr.player2_code AS nvarchar(310)) AS pair_code,
           CAST(d1.last_name + N' / ' + d2.last_name AS nvarchar(300))       AS pair_name,
           CAST(pr.player1_code AS nvarchar(150))                            AS player1_code,
           CAST(pr.player2_code AS nvarchar(150))                            AS player2_code
    FROM pr
    JOIN dbo.vw_Dim_Player d1 ON d1.player_code = pr.player1_code
    JOIN dbo.vw_Dim_Player d2 ON d2.player_code = pr.player2_code
)
SELECT f.*, CHECKSUM(pair_name) AS row_hash
FROM f;
GO

/* DIM_PRODUCT
   is_pro_racket : signature racket of a pro player (see vw_Produits)
   is_sponsor    : the brand sponsors at least one pro player of the catalogue
                   (it sells at least one signature racket)               */
CREATE OR ALTER VIEW dbo.vw_Dim_Product AS
WITH p AS (
    SELECT vp.*,
           CASE WHEN vp.signature_keyword IS NOT NULL OR vp.professional_player = N'tapia' THEN 1 ELSE 0 END AS pro_flag
    FROM dbo.vw_Produits vp
),
f AS (
    SELECT CAST(p.sku AS nvarchar(50))                       AS product_code,
           CAST(p.title AS nvarchar(255))                    AS title,
           CAST(NULLIF(p.product_type, N'') AS nvarchar(100)) AS product_type,
           CAST(NULLIF(p.vendor, N'') AS nvarchar(100))       AS brand_name,
           CAST(MAX(p.pro_flag) OVER (PARTITION BY p.vendor) AS bit) AS is_sponsor,
           CAST(CASE WHEN p.collection LIKE N'[0-9][0-9][0-9][0-9]' THEN p.collection END AS nvarchar(50)) AS collection,
           CAST(CASE WHEN p.frame IN (N'carbone', N'carbon') THEN 1 ELSE 0 END AS bit)     AS is_carbon,
           CAST(CASE WHEN p.surface IN (N'sablée', N'sablee', N'sand') THEN 1 ELSE 0 END AS bit) AS is_sanded,
           CAST(p.pro_flag AS bit)                           AS is_pro_racket,
           CAST(NULLIF(p.racket_type, N'') AS nvarchar(50))  AS racket_type,
           CAST(CASE p.color WHEN N'white' THEN N'blanc' WHEN N'black' THEN N'noir' WHEN N'blue' THEN N'bleu'
                             WHEN N'red' THEN N'rouge' WHEN N'green' THEN N'vert' WHEN N'yellow' THEN N'jaune'
                             WHEN N'pink' THEN N'rose' WHEN N'grey' THEN N'gris' WHEN N'gray' THEN N'gris'
                             ELSE NULLIF(p.color, N'') END AS nvarchar(50)) AS color
    FROM p
)
SELECT f.*,
       CHECKSUM(title, product_type, brand_name, is_sponsor, collection, is_carbon, is_sanded, is_pro_racket, racket_type, color) AS row_hash
FROM f;
GO

/* =====================================================================
   FACTS
   ===================================================================== */

/* FACT_MATCH : 1 row = 1 match
   score is written from the winner's side : "36 75 76(6)" = 3-6 7-5 7-6
   nb_eligible_matches = 1 when an upset is possible (not a walkover and at
   least one seeded pair) ; nb_upsets = 1 when the winner is unseeded against
   a seeded pair, or the worse seed of two seeded pairs.
   points_pairX = sum of the two players' ranking points (January 2026).  */
CREATE OR ALTER VIEW dbo.vw_Fact_Match AS
WITH sets AS (
    SELECT m.match_id, t.value AS token
    FROM dbo.Matchs_SA m
    CROSS APPLY STRING_SPLIT(m.score, N' ') t
    WHERE t.value LIKE N'[0-9][0-9]%'
),
sc AS (
    SELECT match_id,
           COUNT(*)                                                     AS nb_sets,
           SUM(CASE WHEN token LIKE N'%(%' THEN 1 ELSE 0 END)           AS nb_tie_breaks,
           SUM(TRY_CONVERT(int, SUBSTRING(token, 1, 1)))                AS games_winner,
           SUM(TRY_CONVERT(int, SUBSTRING(token, 2, 1)))                AS games_loser
    FROM sets
    GROUP BY match_id
),
pairs AS (
    SELECT mp.match_id, mp.side,
           mp.player1_code + N' + ' + mp.player2_code AS pair_code,
           CASE WHEN d1.ranking_points IS NULL AND d2.ranking_points IS NULL THEN NULL
                ELSE ISNULL(d1.ranking_points, 0) + ISNULL(d2.ranking_points, 0) END AS pair_points
    FROM dbo.vw_Match_Paires mp
    LEFT JOIN dbo.Classement_Codes d1 ON d1.player_code = mp.player1_code
    LEFT JOIN dbo.Classement_Codes d2 ON d2.player_code = mp.player2_code
),
f AS (
    SELECT v.match_id, v.full_date, v.tournament_code, v.round_code, v.match_number,
           p1.pair_code AS pair1_code, p2.pair_code AS pair2_code,
           v.winner,
           v.outcome_code + N'|' + v.pair1_status + N'|' + v.pair2_status AS profile_code,
           sc.nb_sets, sc.nb_tie_breaks, sc.games_winner, sc.games_loser,
           v.seed_pair1, v.seed_pair2,
           p1.pair_points AS points_pair1, p2.pair_points AS points_pair2,
           CASE WHEN v.outcome_code <> N'WO' AND (v.seed_pair1 IS NOT NULL OR v.seed_pair2 IS NOT NULL) THEN 1 ELSE 0 END AS eligible,
           CASE WHEN v.winner = N'pair1' THEN v.seed_pair1 ELSE v.seed_pair2 END AS winner_seed,
           CASE WHEN v.winner = N'pair1' THEN v.seed_pair2 ELSE v.seed_pair1 END AS loser_seed
    FROM dbo.vw_Matchs v
    LEFT JOIN sc ON sc.match_id = v.match_id
    JOIN pairs p1 ON p1.match_id = v.match_id AND p1.side = N'p1'
    JOIN pairs p2 ON p2.match_id = v.match_id AND p2.side = N'p2'
)
SELECT f.full_date,
       CAST(f.tournament_code AS nvarchar(160)) AS tournament_code,
       CAST(f.round_code AS nvarchar(50))       AS round_code,
       f.match_number,
       CAST(f.pair1_code AS nvarchar(310))      AS pair1_code,
       CAST(f.pair2_code AS nvarchar(310))      AS pair2_code,
       CAST(f.winner AS nvarchar(10))           AS winner,
       CAST(f.profile_code AS nvarchar(40))     AS profile_code,
       CAST(f.nb_sets AS tinyint)               AS nb_sets,
       CAST(f.nb_tie_breaks AS tinyint)         AS nb_tie_breaks,
       CAST(f.games_winner AS tinyint)          AS games_winner,
       CAST(f.games_loser AS tinyint)           AS games_loser,
       CAST(CASE WHEN f.eligible = 1
                  AND ((f.winner_seed IS NULL AND f.loser_seed IS NOT NULL)
                    OR (f.winner_seed IS NOT NULL AND f.loser_seed IS NOT NULL AND f.winner_seed > f.loser_seed))
                 THEN 1 ELSE 0 END AS tinyint)  AS nb_upsets,
       f.seed_pair1,
       f.seed_pair2,
       f.points_pair1,
       f.points_pair2,
       CAST(f.eligible AS tinyint)              AS nb_eligible_matches
FROM f;
GO

/* FACT_MARKETING : 1 row = 1 product of the catalogue ; player = signature
   player of the racket, UNKNOWN (-1) for the others                      */
CREATE OR ALTER VIEW dbo.vw_Fact_Marketing AS
SELECT COALESCE(TRY_CONVERT(date, LEFT(p.created_at, 10)), CAST('19000101' AS date)) AS date_added,
       CAST(p.sku AS nvarchar(50))                                              AS product_code,
       CAST(COALESCE(p.signature_player_code, N'UNKNOWN') AS nvarchar(150))     AS player_code,
       TRY_CONVERT(decimal(10, 2), p.price)                                     AS price_eur,
       CAST(1 AS int)                                                           AS nb_products
FROM dbo.vw_Produits p;
GO
