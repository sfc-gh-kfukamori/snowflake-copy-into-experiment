-- =============================================================
-- 03_case3_normal_csv.sql
-- Case 3: FIELD_DELIMITER = ',' + FIELD_OPTIONALLY_ENCLOSED_BY = '"'（正常系・比較用）
-- テストファイル: test_with_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb",ccc,ddd  （フィールド内改行あり、カンマあり）
--   行2: eee,fff,ggg          （通常レコード）
-- 期待: 2 行が正しくロードされ、c1 = "aaa\nbbb"（改行込み）
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TEMPORARY TABLE test_case3 (c1 VARCHAR, c2 VARCHAR, c3 VARCHAR);

COPY INTO test_case3
FROM @~/test_fk/test_with_comma.csv
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM test_case3;

SELECT
    c1,
    c2,
    c3,
    LENGTH(c1)                  AS c1_length,
    CONTAINS(c1, '\n')          AS c1_has_newline,
    REPLACE(c1, '\n', '[LF]')   AS c1_visible
FROM test_case3;

-- 期待する出力:
-- row_count = 2
-- 行1: c1 = "aaa\nbbb"（7文字、改行含む）, c2 = "ccc", c3 = "ddd"
-- 行2: c1 = "eee", c2 = "fff", c3 = "ggg"
