-- =============================================================
-- 03_case3_normal_csv.sql
-- Case 3: FIELD_DELIMITER = ',' + FIELD_OPTIONALLY_ENCLOSED_BY = '"'（正常系・比較用）
-- テストファイル: test_with_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb",ccc,ddd  （フィールド内改行あり、カンマあり）
--   行2: eee,fff,ggg          （通常レコード）
-- 期待: 2 行が正しくロードされ、c1 = "aaa\nbbb"（改行込み）
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TABLE CASE3_NORMAL_CSV (
    c1             VARCHAR,
    c2             VARCHAR,
    c3             VARCHAR,
    c1_length      INT,
    c1_has_newline BOOLEAN,
    c1_visible     VARCHAR
);

COPY INTO CASE3_NORMAL_CSV
FROM (
    SELECT
        $1,
        $2,
        $3,
        LENGTH($1),
        CONTAINS($1, '\n'),
        REPLACE($1, '\n', '[LF]')
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_with_comma.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM CASE3_NORMAL_CSV;

SELECT * FROM CASE3_NORMAL_CSV;

-- 期待する出力:
-- row_count = 2
-- 行1: c1 = "aaa\nbbb"（7文字、改行含む）, c2 = "ccc", c3 = "ddd"
-- 行2: c1 = "eee", c2 = "fff", c3 = "ggg"
