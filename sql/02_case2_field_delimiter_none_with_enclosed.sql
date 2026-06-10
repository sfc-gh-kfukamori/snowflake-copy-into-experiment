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

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TEMPORARY TABLE test_case2 (raw_data VARCHAR);

-- ① デフォルト（ON_ERROR = ABORT_STATEMENT）: エラーで停止
COPY INTO test_case2
FROM @~/test_fk/test_with_comma.csv
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);
-- 期待: エラー "Found character ',' instead of record delimiter '\n'"
-- → FIELD_OPTIONALLY_ENCLOSED_BY が有効なため "aaa\nbbb" を1フィールドと認識するが、
--   その後の ",ccc,ddd" でレコード区切り '\n' を期待してエラー

-- ② ON_ERROR = CONTINUE: エラー行をスキップして続行
TRUNCATE TABLE test_case2;

COPY INTO test_case2
FROM @~/test_fk/test_with_comma.csv
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = CONTINUE;

SELECT COUNT(*) AS row_count FROM test_case2;
SELECT raw_data FROM test_case2;

-- 期待する出力:
-- row_count = 1（1行目はエラースキップ、2行目 "eee,fff,ggg" のみロード）
