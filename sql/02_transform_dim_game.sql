-- Transforms raw data into something SQL can better work with including dates, normalization of pries,, etc

USE steamdb;

INSERT INTO dim_game (
    appid,
    game_name,
    release_date,
    developer,
    publisher,
    initial_price_usd
)
SELECT
    incoming_appid,
    incoming_game_name,
    incoming_release_date,
    incoming_developer,
    incoming_publisher,
    incoming_initial_price
FROM (
    SELECT
        s.appid AS incoming_appid,
        TRIM(r.game_name) AS incoming_game_name,
        STR_TO_DATE(
            s.release_date,
            '%c/%e/%Y'
        ) AS incoming_release_date,
        COALESCE(
            NULLIF(TRIM(r.developers), ''),
            'Unknown'
        ) AS incoming_developer,
        COALESCE(
            NULLIF(TRIM(r.publishers), ''),
            'Unknown'
        ) AS incoming_publisher,
        ROUND(
            COALESCE(s.price, 0.00),
            2
        ) AS incoming_initial_price
    FROM stg_games_raw AS s
    JOIN stg_game_text_repair AS r
        ON s.appid = r.appid
    WHERE s.appid IS NOT NULL
      AND r.game_name IS NOT NULL
      AND TRIM(r.game_name) != ''
) AS incoming
ON DUPLICATE KEY UPDATE
    game_name = incoming_game_name,
    release_date = incoming_release_date,
    developer = incoming_developer,
    publisher = incoming_publisher,
    initial_price_usd = incoming_initial_price;

