-- =============================================================
-- 01_case1_field_delimiter_none_only.sql
-- Case 1: FIELD_DELIMITER = NONE のみ（FIELD_OPTIONALLY_ENCLOSED_BY なし）
-- テストファイル: test_with_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb",ccc,ddd  （フィールド内改行あり、カンマあり）
--   行2: eee,fff,ggg          （通常レコード）
-- 期待: レコードが分断されて 3 行になる
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TEMPORARY TABLE test_case1 (raw_data VARCHAR);

COPY INTO test_case1
FROM @~/test_fk/test_with_comma.csv
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM test_case1;

SELECT
    raw_data,
    LENGTH(raw_data)            AS char_length,
    CONTAINS(raw_data, '"')     AS has_doublequote,
    REPLACE(raw_data, '\n', '[LF]') AS visible_newline
FROM test_case1;

-- 期待する出力:
-- row_count = 3（"aaa / bbb",ccc,ddd / eee,fff,ggg に分断）
-- has_doublequote = TRUE（クォートは文字として残る）
