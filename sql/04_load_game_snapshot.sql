-- Loads required facts for the current date
USE steamdb;
-- Technical load/batch date.
-- The source dataset's actual observation date is unknown.
SET @game_snapshot_date = '2026-09-29';

INSERT INTO fact_game_snapshot (
    appid,
    snapshot_date,
    price_usd,
    positive,
    negative
)
SELECT
    s.appid,
    @game_snapshot_date,
    ROUND(s.price, 2),
    s.positive,
    s.negative
FROM stg_games_raw AS s
JOIN dim_game AS d
    ON s.appid = d.appid
WHERE NOT EXISTS (
    SELECT 1
    FROM fact_game_snapshot AS existing
    WHERE existing.appid = s.appid
      AND existing.snapshot_date = @game_snapshot_date
);