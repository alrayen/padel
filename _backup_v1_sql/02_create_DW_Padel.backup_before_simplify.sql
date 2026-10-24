/* =====================================================================
   DW_Padel : Data Warehouse (constellation)
   FACT_MATCH + FACT_MARKETING, 7 dimensions, DIM_DATE and DIM_PLAYER shared.
   Surrogate keys = IDENTITY (like Client_PK in DW_Ventes) + business code.
   Numbers in INT (no TINYINT / BIT), like the TP.
   Row -1 = "Unknown" member in every dimension.
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

CREATE TABLE dbo.DIM_DATE (
    date_key        INT          NOT NULL CONSTRAINT PK_DIM_DATE PRIMARY KEY,  -- yyyymmdd
    full_date       DATE         NOT NULL,
    [day]           INT          NOT NULL,
    [week]          INT          NOT NULL,
    [month]         INT          NOT NULL,
    [quarter]       INT          NOT NULL,
    [year]          SMALLINT     NOT NULL
);

CREATE TABLE dbo.DIM_TOURNAMENT (
    tournament_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_TOURNAMENT PRIMARY KEY,
    tournament_code     NVARCHAR(160) NOT NULL CONSTRAINT UQ_DIM_TOURNAMENT_code UNIQUE,  -- name + year
    tournament_name     NVARCHAR(150) NOT NULL,
    category            NVARCHAR(100) NULL,
    city                NVARCHAR(100) NULL,
    host_country_code   NVARCHAR(10)  NULL,
    host_continent      NVARCHAR(50)  NULL,
    [year]              SMALLINT      NULL,
    start_date          DATE          NULL,
    end_date            DATE          NULL
);

CREATE TABLE dbo.DIM_ROUND (
    round_key       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_ROUND PRIMARY KEY,
    code            NVARCHAR(50) NOT NULL CONSTRAINT UQ_DIM_ROUND_code UNIQUE,
    sort_order      INT          NOT NULL
);

CREATE TABLE dbo.DIM_MATCH_PROFILE (
    profile_key     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_MATCH_PROFILE PRIMARY KEY,
    profile_code    NVARCHAR(40) NOT NULL CONSTRAINT UQ_DIM_MATCH_PROFILE_code UNIQUE,  -- outcome|pair1|pair2
    outcome_code    NVARCHAR(10) NOT NULL,   -- NORMAL / RET / WO
    pair1_status    NVARCHAR(10) NOT NULL,   -- SEEDED / UNSEEDED
    pair2_status    NVARCHAR(10) NOT NULL,
    CONSTRAINT UQ_DIM_MATCH_PROFILE UNIQUE (outcome_code, pair1_status, pair2_status)
);

CREATE TABLE dbo.DIM_PLAYER (
    player_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PLAYER PRIMARY KEY,
    player_code       NVARCHAR(150) NOT NULL CONSTRAINT UQ_DIM_PLAYER_code UNIQUE,  -- "FIRST LAST" uppercase, no accents
    last_name         NVARCHAR(100) NULL,
    first_name        NVARCHAR(100) NULL,
    gender            NCHAR(1)      NULL,
    country_code      NVARCHAR(10)  NULL,
    continent         NVARCHAR(50)  NULL,
    ranking_position  INT           NULL,
    ranking_points    INT           NULL
);

/* snowflake: DIM_PAIR -> DIM_PLAYER */
CREATE TABLE dbo.DIM_PAIR (
    pair_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PAIR PRIMARY KEY,
    pair_code       NVARCHAR(310) NOT NULL CONSTRAINT UQ_DIM_PAIR_code UNIQUE,  -- player1_code + player2_code
    pair_name       NVARCHAR(300) NOT NULL,
    player1_key     INT NOT NULL CONSTRAINT FK_DIM_PAIR_player1 REFERENCES dbo.DIM_PLAYER(player_key),
    player2_key     INT NOT NULL CONSTRAINT FK_DIM_PAIR_player2 REFERENCES dbo.DIM_PLAYER(player_key),
    CONSTRAINT UQ_DIM_PAIR UNIQUE (player1_key, player2_key)
);

CREATE TABLE dbo.DIM_PRODUCT (
    product_key     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_PRODUCT PRIMARY KEY,
    product_code    NVARCHAR(50)  NOT NULL CONSTRAINT UQ_DIM_PRODUCT_code UNIQUE,  -- sku
    title           NVARCHAR(255) NULL,
    product_type    NVARCHAR(100) NULL,
    brand_name      NVARCHAR(100) NULL,
    collection      NVARCHAR(50)  NULL,
    is_carbon       INT           NULL,
    is_sanded       INT           NULL,
    is_pro_racket   INT           NULL,
    racket_type     NVARCHAR(50)  NULL,
    color           NVARCHAR(50)  NULL
);
GO

/* ---------------- FACTS ---------------- */

/* grain : 1 row = 1 match */
CREATE TABLE dbo.FACT_MATCH (
    date_key            INT NOT NULL CONSTRAINT FK_FM_date       REFERENCES dbo.DIM_DATE(date_key),
    tournament_key      INT NOT NULL CONSTRAINT FK_FM_tournament REFERENCES dbo.DIM_TOURNAMENT(tournament_key),
    round_key           INT NOT NULL CONSTRAINT FK_FM_round      REFERENCES dbo.DIM_ROUND(round_key),
    match_number        INT NOT NULL,                       -- degenerate dimension
    pair1_key           INT NOT NULL CONSTRAINT FK_FM_pair1      REFERENCES dbo.DIM_PAIR(pair_key),
    pair2_key           INT NOT NULL CONSTRAINT FK_FM_pair2      REFERENCES dbo.DIM_PAIR(pair_key),
    winning_pair_key    INT NOT NULL CONSTRAINT FK_FM_winner     REFERENCES dbo.DIM_PAIR(pair_key),
    profile_key         INT NOT NULL CONSTRAINT FK_FM_profile    REFERENCES dbo.DIM_MATCH_PROFILE(profile_key),
    nb_sets             INT     NULL,
    nb_tie_breaks       INT     NULL,
    games_winner        INT     NULL,
    games_loser         INT     NULL,
    nb_upsets           INT     NOT NULL,
    seed_pair1          INT     NULL,
    seed_pair2          INT     NULL,
    points_pair1        INT NULL,
    points_pair2        INT NULL,
    nb_eligible_matches INT     NOT NULL,
    CONSTRAINT PK_FACT_MATCH PRIMARY KEY (tournament_key, match_number)
);

/* grain : 1 row = 1 product in the catalogue */
CREATE TABLE dbo.FACT_MARKETING (
    product_key     INT NOT NULL CONSTRAINT PK_FACT_MARKETING PRIMARY KEY
                        CONSTRAINT FK_FMK_product REFERENCES dbo.DIM_PRODUCT(product_key),
    date_added_key  INT NOT NULL CONSTRAINT FK_FMK_date   REFERENCES dbo.DIM_DATE(date_key),
    player_key      INT NOT NULL CONSTRAINT FK_FMK_player REFERENCES dbo.DIM_PLAYER(player_key),
    price_eur       DECIMAL(10,2) NULL,
    nb_products     INT NOT NULL
);
GO

/* ---------------- UNKNOWN MEMBERS (-1) ---------------- */
INSERT INTO dbo.DIM_DATE (date_key, full_date, [day], [week], [month], [quarter], [year])
VALUES (-1, '1900-01-01', 0, 0, 0, 0, 1900);

SET IDENTITY_INSERT dbo.DIM_TOURNAMENT ON;
INSERT INTO dbo.DIM_TOURNAMENT (tournament_key, tournament_code, tournament_name) VALUES (-1, N'UNKNOWN', N'Unknown');
SET IDENTITY_INSERT dbo.DIM_TOURNAMENT OFF;

SET IDENTITY_INSERT dbo.DIM_ROUND ON;
INSERT INTO dbo.DIM_ROUND (round_key, code, sort_order) VALUES (-1, N'Unknown', 0);
SET IDENTITY_INSERT dbo.DIM_ROUND OFF;

SET IDENTITY_INSERT dbo.DIM_MATCH_PROFILE ON;
INSERT INTO dbo.DIM_MATCH_PROFILE (profile_key, profile_code, outcome_code, pair1_status, pair2_status) VALUES (-1, N'UNKNOWN', N'UNKNOWN', N'UNKNOWN', N'UNKNOWN');
SET IDENTITY_INSERT dbo.DIM_MATCH_PROFILE OFF;

SET IDENTITY_INSERT dbo.DIM_PLAYER ON;
INSERT INTO dbo.DIM_PLAYER (player_key, player_code, last_name, first_name) VALUES (-1, N'UNKNOWN', N'Unknown', N'Unknown');
SET IDENTITY_INSERT dbo.DIM_PLAYER OFF;

SET IDENTITY_INSERT dbo.DIM_PAIR ON;
INSERT INTO dbo.DIM_PAIR (pair_key, pair_code, pair_name, player1_key, player2_key) VALUES (-1, N'UNKNOWN', N'Unknown', -1, -1);
SET IDENTITY_INSERT dbo.DIM_PAIR OFF;

SET IDENTITY_INSERT dbo.DIM_PRODUCT ON;
INSERT INTO dbo.DIM_PRODUCT (product_key, product_code, title) VALUES (-1, N'UNKNOWN', N'Unknown');
SET IDENTITY_INSERT dbo.DIM_PRODUCT OFF;
GO

/* quick check */
SELECT t.name AS table_name, SUM(p.rows) AS nb_rows
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name ORDER BY t.name;
