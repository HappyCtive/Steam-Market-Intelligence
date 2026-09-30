-- Load fact_steamspy_snapshot and create reporting views

-- STEP 1: Populate fact_steamspy_snapshot
USE steamdb;
-- Date inferred from matching archive filenames: 20250101_steamspy_page_*.json
SET @steamspy_snapshot_date = '2025-01-01';

INSERT INTO fact_steamspy_snapshot (
    appid,
    snapshot_date,
    owners_low,
    owners_high
)
SELECT
    s.appid,
    @steamspy_snapshot_date,
    CAST(
        REPLACE(TRIM(SUBSTRING_INDEX(s.owners, '..', 1)), ',', '')
        AS UNSIGNED
    ),
    CAST(
        REPLACE(TRIM(SUBSTRING_INDEX(s.owners, '..', -1)), ',', '')
        AS UNSIGNED
    )
FROM stg_steamspy_raw AS s
JOIN dim_game AS d
    ON s.appid = d.appid
WHERE NOT EXISTS (
    SELECT 1
    FROM fact_steamspy_snapshot AS existing
    WHERE existing.appid = s.appid
      AND existing.snapshot_date = @steamspy_snapshot_date
);


-- One row per game
-- Canonical Excel-ready game-level dataset
CREATE OR REPLACE VIEW vw_game_kpis AS
SELECT
    d.appid,
    d.game_name,
    d.developer,
    d.publisher,
    d.release_date,
    YEAR(d.release_date) AS release_year,

    -- Price from the main game dataset
    d.initial_price_usd AS price_usd,

    CASE
        WHEN d.initial_price_usd = 0 THEN 0
        WHEN d.initial_price_usd < 5 THEN 1
        WHEN d.initial_price_usd < 10 THEN 2
        WHEN d.initial_price_usd < 20 THEN 3
        WHEN d.initial_price_usd < 40 THEN 4
        ELSE 5
    END AS price_bucket_sort,

    CASE
        WHEN d.initial_price_usd = 0 THEN 'Free'
        WHEN d.initial_price_usd < 5 THEN '$0.01–$4.99'
        WHEN d.initial_price_usd < 10 THEN '$5.00–$9.99'
        WHEN d.initial_price_usd < 20 THEN '$10.00–$19.99'
        WHEN d.initial_price_usd < 40 THEN '$20.00–$39.99'
        ELSE '$40.00+'
    END AS price_bucket,

    -- Review metrics
    fg.snapshot_date AS review_load_date,
    fg.positive,
    fg.negative,
    fg.review_count,
    fg.pct_positive,

    CASE
        WHEN COALESCE(fg.review_count, 0) > 0
        THEN 1 ELSE 0
    END AS has_reviews,

    -- SteamSpy ownership estimates
    fss.snapshot_date AS steamspy_snapshot_date,
    fss.owners_low,
    fss.owners_high,

    CASE
        WHEN fss.owners_low IS NOT NULL
         AND fss.owners_high IS NOT NULL
        THEN ROUND(
            (fss.owners_low + fss.owners_high) / 2,
            0
        )
        ELSE NULL
    END AS owners_mid,

    CASE
        WHEN fss.owners_low IS NOT NULL
         AND fss.owners_high IS NOT NULL
        THEN 1 ELSE 0
    END AS has_ownership_estimate,

    -- Tag coverage without multiplying game rows
    COALESCE(tc.tag_count, 0) AS tag_count,

    CASE
        WHEN COALESCE(tc.tag_count, 0) > 0
        THEN 1 ELSE 0
    END AS has_tags

FROM dim_game AS d

LEFT JOIN fact_game_snapshot AS fg
    ON d.appid = fg.appid
   AND fg.snapshot_date = (
        SELECT MAX(fg_latest.snapshot_date)
        FROM fact_game_snapshot AS fg_latest
        WHERE fg_latest.appid = d.appid
   )

LEFT JOIN fact_steamspy_snapshot AS fss
    ON d.appid = fss.appid
   AND fss.snapshot_date = (
        SELECT MAX(fss_latest.snapshot_date)
        FROM fact_steamspy_snapshot AS fss_latest
        WHERE fss_latest.appid = d.appid
   )

LEFT JOIN (
    SELECT
        appid,
        COUNT(*) AS tag_count
    FROM bridge_game_tag
    GROUP BY appid
) AS tc
    ON d.appid = tc.appid;


-- Tag-level market KPIs
-- One row per tag
CREATE OR REPLACE VIEW vw_tag_kpis AS
SELECT
    t.tag_id,
    t.tag_name,

    COUNT(*) AS game_count,

    SUM(g.has_reviews) AS reviewed_games,
    ROUND(
        100.0 * SUM(g.has_reviews) / COUNT(*),
        1
    ) AS review_coverage_pct,

    -- Each game contributes equally
    ROUND(AVG(g.pct_positive), 4)
        AS avg_game_pct_positive,

    -- Each individual review contributes equally
    ROUND(
        SUM(COALESCE(g.positive, 0))
        / NULLIF(SUM(COALESCE(g.review_count, 0)), 0),
        4
    ) AS review_weighted_pct_positive,

    SUM(g.has_ownership_estimate)
        AS ownership_covered_games,

    ROUND(
        100.0 * SUM(g.has_ownership_estimate) / COUNT(*),
        1
    ) AS ownership_coverage_pct,

    ROUND(AVG(g.owners_mid), 0)
        AS avg_owners_mid,

    ROUND(AVG(g.price_usd), 2)
        AS avg_price_usd

FROM dim_tag AS t
JOIN bridge_game_tag AS b
    ON t.tag_id = b.tag_id
JOIN vw_game_kpis AS g
    ON b.appid = g.appid
GROUP BY
    t.tag_id,
    t.tag_name;


-- Price-range KPIs
-- One row per price range
CREATE OR REPLACE VIEW vw_price_buckets AS
SELECT
    price_bucket_sort,
    price_bucket,

    COUNT(*) AS game_count,

    SUM(has_reviews) AS reviewed_games,
    ROUND(
        100.0 * SUM(has_reviews) / COUNT(*),
        1
    ) AS review_coverage_pct,

    ROUND(AVG(pct_positive), 4)
        AS avg_game_pct_positive,

    ROUND(
        SUM(COALESCE(positive, 0))
        / NULLIF(SUM(COALESCE(review_count, 0)), 0),
        4
    ) AS review_weighted_pct_positive,

    ROUND(AVG(review_count), 0)
        AS avg_review_count,

    SUM(has_ownership_estimate)
        AS ownership_covered_games,

    ROUND(
        100.0 * SUM(has_ownership_estimate) / COUNT(*),
        1
    ) AS ownership_coverage_pct,

    ROUND(AVG(owners_mid), 0)
        AS avg_owners_mid

FROM vw_game_kpis
GROUP BY
    price_bucket_sort,
    price_bucket;


-- Release-year KPIs
-- One row per release year
CREATE OR REPLACE VIEW vw_release_trends AS
SELECT
    release_year,

    MIN(release_date) AS first_release_date,
    MAX(release_date) AS last_release_date,

    COUNT(*) AS games_released,
    ROUND(AVG(price_usd), 2) AS avg_price_usd,

    SUM(has_reviews) AS reviewed_games,
    ROUND(
        100.0 * SUM(has_reviews) / COUNT(*),
        1
    ) AS review_coverage_pct,

    ROUND(AVG(pct_positive), 4)
        AS avg_game_pct_positive,

    ROUND(
        SUM(COALESCE(positive, 0))
        / NULLIF(SUM(COALESCE(review_count, 0)), 0),
        4
    ) AS review_weighted_pct_positive,

    SUM(has_ownership_estimate)
        AS ownership_covered_games,

    ROUND(
        100.0 * SUM(has_ownership_estimate) / COUNT(*),
        1
    ) AS ownership_coverage_pct,

    ROUND(AVG(owners_mid), 0)
        AS avg_owners_mid

FROM vw_game_kpis
WHERE release_date IS NOT NULL
GROUP BY release_year;

-- Publisher portfolio KPIs
-- Multiple-publisher combinations remain combined labels

CREATE OR REPLACE VIEW vw_publisher_kpis AS
SELECT
    publisher,

    COUNT(*) AS game_count,
    ROUND(AVG(price_usd), 2) AS avg_price_usd,

    SUM(has_reviews) AS reviewed_games,
    ROUND(
        100.0 * SUM(has_reviews) / COUNT(*),
        1
    ) AS review_coverage_pct,

    ROUND(AVG(pct_positive), 4)
        AS avg_game_pct_positive,

    ROUND(
        SUM(COALESCE(positive, 0))
        / NULLIF(SUM(COALESCE(review_count, 0)), 0),
        4
    ) AS review_weighted_pct_positive,

    SUM(has_ownership_estimate)
        AS ownership_covered_games,

    ROUND(
        100.0 * SUM(has_ownership_estimate) / COUNT(*),
        1
    ) AS ownership_coverage_pct,

    ROUND(AVG(owners_mid), 0)
        AS avg_owners_mid

FROM vw_game_kpis
GROUP BY publisher;


-- VERIFICATION

-- How do Steam price ranges differ in supply, review sentiment, review volume, and ownership estimates?
SELECT *
FROM steamdb.vw_price_buckets
ORDER BY price_bucket_sort;

-- Which tags combine meaningful market supply with stronger sentiment and ownership estimates?
SELECT *
FROM steamdb.vw_tag_kpis
ORDER BY game_count DESC
LIMIT 20;

-- How have release volume, pricing, sentiment, and ownership estimates differed by release year?
SELECT *
FROM steamdb.vw_release_trends
ORDER BY release_year;

-- Which publishers have larger portfolios, and how do their portfolios compare on sentiment and ownership estimates?
SELECT *
FROM steamdb.vw_publisher_kpis
WHERE publisher != 'Unknown'
ORDER BY game_count DESC
LIMIT 20;


CREATE OR REPLACE VIEW vw_dataset_summary AS
SELECT
    COUNT(*) AS total_games,
    SUM(has_reviews) AS reviewed_games,
    ROUND(
        100.0 * SUM(has_reviews) / COUNT(*),
        1
    ) AS review_coverage_pct,
    SUM(has_ownership_estimate) AS ownership_covered_games,
    ROUND(
        100.0 * SUM(has_ownership_estimate) / COUNT(*),
        1
    ) AS ownership_coverage_pct,
    SUM(has_tags) AS tagged_games,
    ROUND(
        100.0 * SUM(has_tags) / COUNT(*),
        1
    ) AS tag_coverage_pct,
    SUM(COALESCE(review_count, 0)) AS total_reviews,
    ROUND(AVG(pct_positive), 4)
        AS avg_game_pct_positive,
    ROUND(AVG(price_usd), 2)
        AS avg_price_usd
FROM vw_game_kpis;

