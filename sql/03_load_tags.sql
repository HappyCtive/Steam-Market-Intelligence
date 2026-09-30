-- 04_tags_load.sql
-- Purpose: 
-- Normalize tags from staging into dim_tag and bridge_game_tag

-- STEP 1: Insert distinct tags into dim_tag
USE steamdb;

INSERT INTO dim_tag (tag_name)
SELECT incoming_tag_name
FROM (
	SELECT DISTINCT tag_name AS incoming_tag_name
    FROM stg_game_tags
	WHERE tag_name IS NOT NULL
		AND tag_name != ''
) AS incoming
ON DUPLICATE KEY UPDATE tag_name = VALUES(tag_name);


-- STEP 2: Populate bridge_game_tag
INSERT INTO bridge_game_tag (appid, tag_id)
SELECT incoming_appid, incoming_tag_id
FROM (
    SELECT DISTINCT
        s.appid AS incoming_appid,
        t.tag_id AS incoming_tag_id
    FROM stg_game_tags AS s
    JOIN dim_tag AS t
        ON s.tag_name = t.tag_name
    JOIN dim_game AS d
        ON s.appid = d.appid
) AS incoming
ON DUPLICATE KEY UPDATE appid = incoming_appid;

-- check tags
SELECT COUNT(*) AS total_tags        FROM dim_tag;
SELECT COUNT(*) AS total_bridge_rows FROM bridge_game_tag;

-- Spot check a specific game's tags
SELECT d.game_name, t.tag_name
FROM dim_game d
JOIN bridge_game_tag b ON d.appid = b.appid
JOIN dim_tag t         ON b.tag_id = t.tag_id
WHERE d.appid = 570;