-- =============================================================
-- 04_case4_no_comma_with_enclosed.sql
-- Case 4: FIELD_DELIMITER = NONE + FIELD_OPTIONALLY_ENCLOSED_BY = '"'（カンマなしCSV）
-- テストファイル: test_no_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb"  （フィールド内改行あり、カンマなし・1カラムCSV）
--   行2: eee          （通常レコード）
-- 期待: 2 行が正しくロードされ、クォートがストリップされて改行が保持される
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TEMPORARY TABLE test_case4 (raw_data VARCHAR);

COPY INTO test_case4
FROM @~/test_fk/test_no_comma.csv
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM test_case4;

SELECT
    raw_data,
    LENGTH(raw_data)                AS char_length,
    CONTAINS(raw_data, '"')         AS has_doublequote,
    CONTAINS(raw_data, '\n')        AS has_newline,
    REPLACE(raw_data, '\n', '[LF]') AS visible_newline
FROM test_case4;

-- 期待する出力:
-- row_count = 2
-- 行1: raw_data = "aaa\nbbb"（7文字、クォートなし、改行含む）
-- 行2: raw_data = "eee"（3文字）
-- → FIELD_OPTIONALLY_ENCLOSED_BY は FIELD_DELIMITER = NONE でも有効であることを確認
