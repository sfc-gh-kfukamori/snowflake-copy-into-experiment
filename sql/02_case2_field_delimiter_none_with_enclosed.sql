-- =============================================================
-- 02_case2_field_delimiter_none_with_enclosed.sql
-- Case 2: FIELD_DELIMITER = NONE + FIELD_OPTIONALLY_ENCLOSED_BY = '"'
-- テストファイル: test_with_comma.csv
-- ファイル内容:
--   行1: "aaa\nbbb",ccc,ddd  （フィールド内改行あり、カンマあり）
--   行2: eee,fff,ggg          （通常レコード）
-- 期待: FIELD_OPTIONALLY_ENCLOSED_BY は有効だが、
--       クォート閉じ後の ",ccc,ddd" でエラーになる
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------
-- エラー内容を記録するログテーブル
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE CASE2_ERROR_LOG (
    file_name    VARCHAR,
    error_line   INT,
    error_detail VARCHAR
);

-- COPY INTO を ABORT_STATEMENT（デフォルト）で実行するとこのエラーが発生する:
--   "Found character ',' instead of record delimiter '\n'
--    File '...test_with_comma.csv', line 2, character 5"
-- FIELD_OPTIONALLY_ENCLOSED_BY が有効なため "aaa\nbbb" を1フィールドと認識するが、
-- その後の ,ccc,ddd でレコード区切り '\n' を期待してエラーになる。
INSERT INTO CASE2_ERROR_LOG VALUES (
    'test_with_comma.csv',
    2,
    'Found character '','' instead of record delimiter ''\n'' at line 2, character 5. '
    || 'FIELD_OPTIONALLY_ENCLOSED_BY は有効なため "aaa\nbbb" をクォートフィールドとして認識したが、'
    || 'その後の ,ccc,ddd でレコード区切りを期待してエラー。'
);

-- ---------------------------------------------------------------
-- ON_ERROR = CONTINUE でロード（エラー行スキップ、正常行のみ保存）
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE CASE2_NONE_WITH_ENCLOSED_BY (
    raw_data        VARCHAR,
    char_length     INT,
    has_doublequote BOOLEAN,
    visible_newline VARCHAR,
    load_note       VARCHAR
);

COPY INTO CASE2_NONE_WITH_ENCLOSED_BY (raw_data, char_length, has_doublequote, visible_newline)
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
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = CONTINUE;

UPDATE CASE2_NONE_WITH_ENCLOSED_BY
SET load_note = '行2のみロード成功。行1はエラースキップ（CASE2_ERROR_LOG 参照）';

-- 結果確認
SELECT * FROM CASE2_NONE_WITH_ENCLOSED_BY;
SELECT * FROM CASE2_ERROR_LOG;

-- 期待する出力:
-- CASE2_NONE_WITH_ENCLOSED_BY: row_count = 1（eee,fff,ggg のみロード）
-- CASE2_ERROR_LOG: 行1のエラー詳細が記録されている
