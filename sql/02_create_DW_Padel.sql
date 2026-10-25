/* =====================================================================
   DW_Padel : Data Warehouse (constellation)
   FACT_MATCH + FACT_MARKETING, 7 dimensions, DIM_DATE and DIM_PLAYER shared.
   Surrogate keys = IDENTITY (like Client_PK in DW_Ventes).
   Business key = the value as it is written in the source files
   (tournament name + start date, "Round of 64", the score, the player's name).
   The fact tables hold only keys and values taken from the source:
   everything calculated lives in the dimensions.
   ===================================================================== */
IF DB_ID('DW_Padel') IS NULL CREATE DATABASE DW_Padel;
GO
USE DW_Padel;
GO

/* drop facts first (they reference the dimensions) */
DROP TABLE IF EXISTS dbo.FACT_MATCH;
DROP TABLE IF EXISTS dbo.FACT_MARKETING;
DROP TABLE IF EXISTS dbo.DIM_PAIR;
DROP TABLE IF EXISTS dbo.DIM_PLAYER;
DROP TABLE IF EXISTS dbo.DIM_DATE;
DROP TABLE IF EXISTS dbo.DIM_TOURNAMENT;
DROP TABLE IF EXISTS dbo.DIM_ROUND;
DROP TABLE IF EXISTS dbo.DIM_MATCH_PROFILE;
DROP TABLE IF EXISTS dbo.DIM_PRODUCT;
GO

/* ---------------- DIMENSIONS ---------------- */

/* filled by the Execute SQL Task "dim date" (one row per day) */
CREATE TABLE dbo.DIM_DATE (
    date_key        INT      NOT NULL CONSTRAINT PK_DIM_DATE PRIMARY KEY,   -- yyyymmdd
    full_date       DATE     NOT NULL,
    [day]           INT      NOT NULL,
    [week]          INT      NOT NULL,
    [month]         INT      NOT NULL,
    [quarter]       INT      NOT NULL,
    [year]          SMALLINT NOT NULL
);

/* calendars 2023, 2024, 2025, 2026 (one row per tournament) */
CREATE TABLE dbo.DIM_TOURNAMENT (
    tournament_key     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_TOURNAMENT PRIMARY KEY,
    tournament_name    NVARCHAR(150) NOT NULL,
    start_date         DATE          NOT NULL,
    end_date           DATE          NULL,
    category           NVARCHAR(100) NULL,
    host_country_code  NVARCHAR(10)  NULL,
    host_continent     NVARCHAR(50)  NULL,
    CONSTRAINT UQ_DIM_TOURNAMENT UNIQUE (tournament_name, start_date)       -- business key
);

/* "Round of 64" ... "Final", as in the files */
CREATE TABLE dbo.DIM_ROUND (
    round_key   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_ROUND PRIMARY KEY,
    round_name  NVARCHAR(50) NOT NULL CONSTRAINT UQ_DIM_ROUND UNIQUE,        -- business key
    sort_order  INT          NOT NULL                                     -- 1 = Round of 64 ... 7 = Final
);

/* one row per score written in the files ("62 67(7) 62", "46 11 RET", "WO") */
CREATE TABLE dbo.DIM_MATCH_PROFILE (
    profile_key    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_MATCH_PROFILE PRIMARY KEY,
    score          NVARCHAR(50) NOT NULL CONSTRAINT UQ_DIM_MATCH_PROFILE UNIQUE,  -- business key
    outcome_code   NVARCHAR(10) NOT NULL,      -- NORMAL / RET / WO
    nb_sets        INT          NOT NULL,
    nb_tie_breaks  INT          NOT NULL
);

/* official ranking, men + women */
CREATE TABLE dbo.DIM_PLAYER (
    player_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PLAYER PRIMARY KEY,
    player_name       NVARCHAR(150) NOT NULL CONSTRAINT UQ_DIM_PLAYER UNIQUE,  -- business key ("Arturo Coello")
    gender            NCHAR(1)      NULL,
    country_code      NVARCHAR(10)  NULL,
    continent         NVARCHAR(50)  NULL,
    ranking_position  INT           NULL,
    ranking_points    INT           NULL
);

/* snowflake: DIM_PAIR -> DIM_PLAYER
   a pair is kept in the order written in the draw; pair_name is the same
   for both orders (alphabetical), so Power BI groups them together */
CREATE TABLE dbo.DIM_PAIR (
    pair_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PAIR PRIMARY KEY,
    player1_name  NVARCHAR(150) NOT NULL,
    player2_name  NVARCHAR(150) NOT NULL,
    pair_name     NVARCHAR(310) NOT NULL,
    player1_key   INT NULL CONSTRAINT FK_DIM_PAIR_player1 REFERENCES dbo.DIM_PLAYER(player_key),
    player2_key   INT NULL CONSTRAINT FK_DIM_PAIR_player2 REFERENCES dbo.DIM_PLAYER(player_key),
    CONSTRAINT UQ_DIM_PAIR UNIQUE (player1_name, player2_name)              -- business key
);

/* shop catalogue (padel_rackets.csv) */
CREATE TABLE dbo.DIM_PRODUCT (
    product_key    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PRODUCT PRIMARY KEY,
    product_code   NVARCHAR(50)  NOT NULL CONSTRAINT UQ_DIM_PRODUCT UNIQUE,  -- sku
    title          NVARCHAR(255) NULL,
    product_type   NVARCHAR(100) NULL,
    brand_name     NVARCHAR(100) NULL,
    collection     NVARCHAR(50)  NULL,
    color          NVARCHAR(50)  NULL,
    racket_type    NVARCHAR(50)  NULL,
    is_carbon      INT           NULL,
    is_sanded      INT           NULL,
    is_pro_racket  INT           NULL,
    date_added     DATE          NULL,
    player_name    NVARCHAR(150) NULL            -- player found in the title ("Head Coello Pro" -> Arturo Coello)
);
GO

/* ---------------- FACTS : keys + values from the source only ---------------- */

/* grain : 1 row = 1 match */
CREATE TABLE dbo.FACT_MATCH (
    date_key          INT NOT NULL CONSTRAINT FK_FM_date       REFERENCES dbo.DIM_DATE(date_key),
    tournament_key    INT NOT NULL CONSTRAINT FK_FM_tournament REFERENCES dbo.DIM_TOURNAMENT(tournament_key),
    round_key         INT NOT NULL CONSTRAINT FK_FM_round      REFERENCES dbo.DIM_ROUND(round_key),
    match_number      INT NOT NULL,                              -- degenerate dimension (match_id), information only
    pair1_key         INT NOT NULL CONSTRAINT FK_FM_pair1      REFERENCES dbo.DIM_PAIR(pair_key),
    pair2_key         INT NOT NULL CONSTRAINT FK_FM_pair2      REFERENCES dbo.DIM_PAIR(pair_key),
    winning_pair_key  INT NOT NULL CONSTRAINT FK_FM_winner     REFERENCES dbo.DIM_PAIR(pair_key),
    profile_key       INT NOT NULL CONSTRAINT FK_FM_profile    REFERENCES dbo.DIM_MATCH_PROFILE(profile_key),
    seed_pair1        INT NOT NULL,                              -- 0 = not seeded
    seed_pair2        INT NOT NULL,
    CONSTRAINT PK_FACT_MATCH PRIMARY KEY (tournament_key, round_key, pair1_key, pair2_key)   -- one match = tournament + round + the 2 pairs
);

/* grain : 1 row = 1 product in the catalogue */
CREATE TABLE dbo.FACT_MARKETING (
    product_key     INT NOT NULL CONSTRAINT PK_FACT_MARKETING PRIMARY KEY
                        CONSTRAINT FK_FMK_product REFERENCES dbo.DIM_PRODUCT(product_key),
    date_added_key  INT NOT NULL CONSTRAINT FK_FMK_date   REFERENCES dbo.DIM_DATE(date_key),
    player_key      INT NULL     CONSTRAINT FK_FMK_player REFERENCES dbo.DIM_PLAYER(player_key),  -- NULL = no player in the title
    price_eur       DECIMAL(10,2) NULL
);
GO

/* quick check */
SELECT t.name AS table_name, SUM(p.rows) AS nb_rows
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name ORDER BY t.name;
