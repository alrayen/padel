/* =====================================================================
   DIM_DATE : auto-generated (Execute SQL Task "dim date" of ETL_SA_DW)
   One row per day, from 1 January of the oldest year found in the SA
   to 31 December of the most recent year.
   Sources of dates : matches, calendars (start / end), rackets (created_at).
   Only the missing days are inserted -> the task can be run again safely.
   ===================================================================== */
DECLARE @debut date, @fin date, @d date;

SELECT @debut = DATEFROMPARTS(MIN(YEAR(d)), 1, 1),
       @fin   = DATEFROMPARTS(MAX(YEAR(d)), 12, 31)
FROM (
          SELECT TRY_CONVERT(date, [date])              AS d FROM SA_Padel.dbo.Matchs_SA
    UNION ALL SELECT TRY_CONVERT(date, start_date)           FROM SA_Padel.dbo.Calendrier_SA
    UNION ALL SELECT TRY_CONVERT(date, end_date)             FROM SA_Padel.dbo.Calendrier_SA
    UNION ALL SELECT TRY_CONVERT(date, LEFT(created_at, 10)) FROM SA_Padel.dbo.Produits_SA
) x
WHERE d IS NOT NULL;

SET @d = @debut;
WHILE @d <= @fin
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_DATE WHERE full_date = @d)
        INSERT INTO dbo.DIM_DATE (date_key, full_date, [day], [week], [month], [quarter], [year])
        VALUES (CONVERT(int, CONVERT(char(8), @d, 112)),   -- 20250908
                @d,
                DAY(@d),
                DATEPART(ISO_WEEK, @d),
                MONTH(@d),
                DATEPART(QUARTER, @d),
                YEAR(@d));
    SET @d = DATEADD(DAY, 1, @d);
END
