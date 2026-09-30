-- Creation of schema tables

CREATE DATABASE IF NOT EXISTS steamDB
	DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE steamDB;

-- DIMENSION 
CREATE TABLE IF NOT EXISTS dim_game (
    appid INT NOT NULL,
    game_name TEXT NOT NULL,
    release_date DATE NULL,
    developer TEXT NOT NULL,
    publisher VARCHAR(255) NOT NULL,
    initial_price_usd DECIMAL(10,2) NULL,

    PRIMARY KEY (appid),
    KEY idx_game_release_date (release_date),
    KEY idx_game_publisher (publisher),
    KEY idx_game_developer (developer(255))
) ENGINE = InnoDB;


-- Collecting tags from games
CREATE TABLE IF NOT EXISTS dim_tag(
	tag_id INT NOT NULL AUTO_INCREMENT,
	tag_name VARCHAR(120) NOT NULL,
	PRIMARY KEY (tag_id),
	UNIQUE KEY uq_tag_name (tag_name)
) ENGINE=InnoDB;

-- BRIDGE 
CREATE TABLE IF NOT EXISTS bridge_game_tag (
  appid INT NOT NULL,
  tag_id INT NOT NULL,
  PRIMARY KEY (appid, tag_id),
  KEY idx_bgt_tag_app (tag_id, appid),
  CONSTRAINT fk_bgt_game FOREIGN KEY (appid) REFERENCES dim_game(appid),
  CONSTRAINT fk_bgt_tag  FOREIGN KEY (tag_id) REFERENCES dim_tag(tag_id)
) ENGINE=InnoDB;

-- FACTS 
CREATE TABLE IF NOT EXISTS fact_game_snapshot (
  appid INT NOT NULL,
  snapshot_date DATE NOT NULL,
  price_usd DECIMAL(10,2) NULL,
  positive INT NULL,
  negative INT NULL,
  review_count INT AS (COALESCE(positive,0) + COALESCE(negative,0)) STORED,
  pct_positive DECIMAL(6,5) AS (
    CASE
      WHEN (COALESCE(positive,0) + COALESCE(negative,0)) = 0 THEN NULL
      ELSE COALESCE(positive,0) / (COALESCE(positive,0) + COALESCE(negative,0))
    END
  ) STORED,
  PRIMARY KEY (appid, snapshot_date),
  KEY idx_fgs_snapshot_date (snapshot_date),
  CONSTRAINT fk_fgs_game FOREIGN KEY (appid) REFERENCES dim_game(appid)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS fact_reviews_month (
  appid INT NOT NULL,
  year_mon DATE NOT NULL,     -- store as first day of month, e.g. 2024-07-01
  reviews_total INT NOT NULL,
  positive INT NULL,
  negative INT NULL,
  pct_positive DECIMAL(6,5) NULL,
  PRIMARY KEY (appid, year_mon),
  KEY idx_frm_month_app (year_mon, appid),
  CONSTRAINT fk_frm_game FOREIGN KEY (appid) REFERENCES dim_game(appid)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS fact_steamspy_snapshot (
  appid INT NOT NULL,
  snapshot_date DATE NOT NULL,
  owners_low INT NULL,
  owners_high INT NULL,
  players_2weeks INT NULL,
  average_forever INT NULL,
  average_2weeks INT NULL,
  median_forever INT NULL,
  median_2weeks INT NULL,
  PRIMARY KEY (appid, snapshot_date),
  KEY idx_fss_snapshot_date (snapshot_date),
  CONSTRAINT fk_fss_game FOREIGN KEY (appid) REFERENCES dim_game(appid)
) ENGINE=InnoDB;

-- STAGING (RAW IMPORT)
CREATE TABLE stg_games_raw (
    appid INT NOT NULL PRIMARY KEY,
    game_name TEXT NULL,
    release_date VARCHAR(25) NULL,
    estimated_owners VARCHAR(55) NULL,
    peak_ccu INT NULL,
    dlc_count INT NULL,
    price DECIMAL(10,2) NULL,
    max_discount INT NULL,
    about_the_game LONGTEXT NULL,
    supported_languages TEXT NULL,
    full_audio_languages TEXT NULL,
    reviews LONGTEXT NULL,
    header_image TEXT NULL,
    website VARCHAR(255) NULL,
    support_url TEXT NULL,
    support_email VARCHAR(255) NULL,
    windows TINYINT(1) NULL,
    mac TINYINT(1) NULL,
    linux TINYINT(1) NULL,
    metacritic_score INT NULL,
    metacritic_url VARCHAR(255) NULL,
    user_score INT NULL,
    positive INT NULL,
    negative INT NULL,
    achievements INT NULL,
    recommendations INT NULL,
    notes TEXT NULL,
    avg_playtime_forever INT NULL,
    avg_playtime_two_weeks INT NULL,
    median_playtime_forever INT NULL,
    median_playtime_two_weeks INT NULL,
    developers TEXT NULL,
    publishers VARCHAR(255) NULL,
    categories TEXT NULL,
    genres TEXT NULL,
    tags TEXT NULL,
    screenshots LONGTEXT NULL,
    movies TEXT NULL
);

CREATE TABLE IF NOT EXISTS stg_game_tags (
    appid INT NOT NULL,
    tag_name VARCHAR(120) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_steamspy_raw (
	appid INT NOT NULL PRIMARY KEY,
    name TEXT NULL,
	developer VARCHAR(255) NULL,
    publisher VARCHAR(255) NULL,
    score_rank VARCHAR(80) NULL,
    positive INT NULL,
    negative INT NULL,
    userscore INT NULL,
    owners VARCHAR(255) NULL,
    average_forever INT NULL,
    average_2weeks INT NULL,
	median_forever INT NULL,
    median_2weeks INT NULL,
    price DECIMAL(10,2) NULL,
    initialprice DECIMAL(10,2) NULL,
    discount DECIMAL(5,2) NULL,
    ccu INT NULL
);

CREATE TABLE IF NOT EXISTS stg_game_text_repair (
    appid INT NOT NULL,
    game_name TEXT NULL,
    developers TEXT NULL,
    publishers VARCHAR(255) NULL,

    PRIMARY KEY (appid)
) ENGINE = InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;