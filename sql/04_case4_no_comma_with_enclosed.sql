-- =============================================================
-- 04_case4_no_comma_with_enclosed.sql
-- Case 4: FIELD_DELIMITER = NONE + FIELD_OPTIONALLY_ENCLOSED_BY = '"'（カンマなしCSV）
-- テストファイル: test_no_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb"  （フィールド内改行あり、カンマなし・1カラムCSV）
--   行2: eee          （通常レコード）
-- 期待: 2 行が正しくロードされ、クォートがストリップされて改行が保持される
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TABLE CASE4_NO_COMMA_WITH_ENCLOSED_BY (
    raw_data        VARCHAR,
    char_length     INT,
    has_doublequote BOOLEAN,
    has_newline     BOOLEAN,
    visible_newline VARCHAR
);

COPY INTO CASE4_NO_COMMA_WITH_ENCLOSED_BY
FROM (
    SELECT
        $1,
        LENGTH($1),
        CONTAINS($1, '"'),
        CONTAINS($1, '\n'),
        REPLACE($1, '\n', '[LF]')
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_no_comma.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 結果確認
SELECT COUNT(*) AS row_count FROM CASE4_NO_COMMA_WITH_ENCLOSED_BY;

SELECT * FROM CASE4_NO_COMMA_WITH_ENCLOSED_BY;

-- 期待する出力:
-- row_count = 2
-- 行1: raw_data = "aaa\nbbb"（7文字、クォートなし、改行含む）
-- 行2: raw_data = "eee"（3文字）
-- → FIELD_OPTIONALLY_ENCLOSED_BY は FIELD_DELIMITER = NONE でも有効であることを確認
