-- =============================================================
-- 00_setup.sql
-- 実験環境のセットアップ
-- 接続: SZ20347
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

-- テスト用テーブルの作成
CREATE OR REPLACE TEMPORARY TABLE test_case1 (raw_data VARCHAR);
CREATE OR REPLACE TEMPORARY TABLE test_case2 (raw_data VARCHAR);
CREATE OR REPLACE TEMPORARY TABLE test_case3 (c1 VARCHAR, c2 VARCHAR, c3 VARCHAR);
CREATE OR REPLACE TEMPORARY TABLE test_case4 (raw_data VARCHAR);

-- CSVファイルをユーザーステージにアップロード（PUT は snow CLI から実行）
-- snow sql -q "PUT file:///path/to/data/test_with_comma.csv @~/test_fk/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE" --connection SZ20347
-- snow sql -q "PUT file:///path/to/data/test_no_comma.csv   @~/test_fk/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE" --connection SZ20347

-- ステージ確認
LIST @~/test_fk/;
