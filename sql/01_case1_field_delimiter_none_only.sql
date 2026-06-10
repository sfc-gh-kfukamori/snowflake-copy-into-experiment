-- =============================================================
-- 01_case1_field_delimiter_none_only.sql
-- Case 1: FIELD_DELIMITER = NONE のみ（FIELD_OPTIONALLY_ENCLOSED_BY なし）
-- テストファイル: test_with_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb",ccc,ddd  （フィールド内改行あり、カンマあり）
--   行2: eee,fff,ggg          （通常レコード）
-- 期待: レコードが分断されて 3 行になる
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TABLE CASE1_FIELD_DELIMITER_NONE (
    raw_data        VARCHAR,
    char_length     INT,
    has_doublequote BOOLEAN,
    visible_newline VARCHAR
);

COPY INTO CASE1_FIELD_DELIMITER_NONE
FROM (
    SELECT
        $1,
        LENGTH($1),
        CONTAINS($1, '"'),
        REPLACE($1, '\n', '[LF]')
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_with_comma.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM CASE1_FIELD_DELIMITER_NONE;

SELECT * FROM CASE1_FIELD_DELIMITER_NONE;

-- 期待する出力:
-- row_count = 3（"aaa / bbb",ccc,ddd / eee,fff,ggg に分断）
-- has_doublequote = TRUE（クォートは文字として残る）
