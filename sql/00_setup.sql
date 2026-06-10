-- =============================================================
-- 00_setup.sql
-- 実験環境のセットアップ
-- 接続: K_FUKAMORI（アカウントロケータ: ZX48016）
-- =============================================================

-- データベース・スキーマ作成
CREATE DATABASE IF NOT EXISTS CSV_EXPERIMENT_DB;
CREATE SCHEMA IF NOT EXISTS CSV_EXPERIMENT_DB.PUBLIC;

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

-- 名前付き内部ステージ作成
CREATE OR REPLACE STAGE csv_load_stage;

-- CSVファイルをステージにアップロード
-- snow CLI のセッショントークンが無効な場合は Python コネクタを使用すること
--
-- 【Python コネクタを使う方法（推奨）】
-- python3 -c "
-- import snowflake.connector
-- conn = snowflake.connector.connect(connection_name='K_FUKAMORI')
-- cur = conn.cursor()
-- for f in ['test_with_comma.csv', 'test_no_comma.csv', 'test_with_header.csv']:
--     cur.execute(f'PUT file:///path/to/data/{f} @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE')
--     print(cur.fetchall())
-- conn.close()
-- "
--
-- 【snow CLI を使う方法】
-- snow sql -q "PUT file:///path/to/data/test_with_comma.csv  @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE" --connection K_FUKAMORI
-- snow sql -q "PUT file:///path/to/data/test_no_comma.csv    @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE" --connection K_FUKAMORI
-- snow sql -q "PUT file:///path/to/data/test_with_header.csv @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE" --connection K_FUKAMORI

-- ステージ確認
LIST @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage;
