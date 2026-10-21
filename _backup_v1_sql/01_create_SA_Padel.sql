/* =====================================================================
   SA_Padel : Staging Area (zone de transit)
   Raw copy of the professor's CSV files. Columns = CSV headers, all text.
   Emptied (DELETE) before each load by the package EL_SRC_SA.
   ===================================================================== */
IF DB_ID('SA_Padel') IS NULL CREATE DATABASE SA_Padel;
GO
USE SA_Padel;
GO

DROP TABLE IF EXISTS dbo.Matchs_SA;
DROP TABLE IF EXISTS dbo.Calendrier_SA;
DROP TABLE IF EXISTS dbo.Joueurs_SA;
DROP TABLE IF EXISTS dbo.Produits_SA;
DROP TABLE IF EXISTS dbo.Pays_SA;
GO

/* 11 files Tournament-*.csv (Foreach Loop Container) */
CREATE TABLE dbo.Matchs_SA (
    match_id        INT IDENTITY(1,1) NOT NULL,   -- keeps the file order -> match_number
    tournament      NVARCHAR(150),
    [date]          NVARCHAR(20),
    [round]         NVARCHAR(50),
    pair1_player1   NVARCHAR(150),
    pair1_country1  NVARCHAR(10),
    pair1_player2   NVARCHAR(150),
    pair1_country2  NVARCHAR(10),
    pair1_seed      NVARCHAR(10),
    pair2_player1   NVARCHAR(150),
    pair2_country1  NVARCHAR(10),
    pair2_player2   NVARCHAR(150),
    pair2_country2  NVARCHAR(10),
    pair2_seed      NVARCHAR(10),
    winner          NVARCHAR(10),
    score           NVARCHAR(50),
    source_file     NVARCHAR(260)                 -- Derived Column from @[User::Nomfichier]
);

/* calendar-2023.csv + calendar-2024.csv + 2026-PadelTour.csv (Union All) */
CREATE TABLE dbo.Calendrier_SA (
    tournament      NVARCHAR(150),
    category        NVARCHAR(100),
    country         NVARCHAR(100),
    start_date      NVARCHAR(20),
    end_date        NVARCHAR(20),
    source_file     NVARCHAR(260)                 -- Derived Column constant per source
);

/* men-Players.csv + women-Players.csv (Union All) */
CREATE TABLE dbo.Joueurs_SA (
    name            NVARCHAR(150),
    country         NVARCHAR(10),
    points          NVARCHAR(20),
    position        NVARCHAR(20),
    move            NVARCHAR(20),
    gender          NVARCHAR(1)                   -- Derived Column "M" / "F"
);

/* padel_rackets.csv */
CREATE TABLE dbo.Produits_SA (
    title               NVARCHAR(255),
    handle              NVARCHAR(255),
    vendor              NVARCHAR(100),
    product_type        NVARCHAR(100),
    tags                NVARCHAR(500),
    created_at          NVARCHAR(50),
    price               NVARCHAR(20),
    sku                 NVARCHAR(50),
    image               NVARCHAR(500),
    weight              NVARCHAR(50),
    shape               NVARCHAR(50),
    foam                NVARCHAR(50),
    collection          NVARCHAR(50),
    game_level          NVARCHAR(50),
    frame               NVARCHAR(50),
    surface             NVARCHAR(50),
    professional_player NVARCHAR(100),
    color               NVARCHAR(50),
    racket_type         NVARCHAR(50),
    balance             NVARCHAR(50),
    gender              NVARCHAR(50),
    racket_cover        NVARCHAR(50)
);

/* pays.csv : reference file (country code -> name -> continent) */
CREATE TABLE dbo.Pays_SA (
    country_code    NVARCHAR(10),
    country_name    NVARCHAR(100),
    continent       NVARCHAR(50)
);
GO
