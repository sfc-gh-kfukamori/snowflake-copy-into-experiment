-- =============================================================
-- 05_variant_load_patterns.sql
-- 参考: VARIANT型へのロードパターン集
-- フィールド内改行を含むCSVを VARIANT 型にロードする実用的なアプローチ
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------
-- パターンA: フィールド内改行なし → FIELD_DELIMITER=NONE + TO_VARIANT
-- ---------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE bronze_no_newline (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

COPY INTO bronze_no_newline (inserted_at, raw_data)
FROM (
    SELECT CURRENT_TIMESTAMP(), TO_VARIANT($1)
    FROM @~/test_fk/test_with_comma.csv  -- 改行なしファイルを使う場合
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
);


-- ---------------------------------------------------------------
-- パターンB: フィールド内改行あり → OBJECT_CONSTRUCT（カラム数固定）
-- ---------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE bronze_with_newline_obj (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

COPY INTO bronze_with_newline_obj (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'c1', $1,
            'c2', $2,
            'c3', $3
        )
    FROM @~/test_fk/test_with_comma.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ESCAPE_UNENCLOSED_FIELD = NONE
    NULL_IF = ('')
);

SELECT inserted_at, raw_data FROM bronze_with_newline_obj;


-- ---------------------------------------------------------------
-- パターンC: フィールド内改行あり → ARRAY_CONSTRUCT（カラム数不定）
-- ---------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE bronze_with_newline_arr (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

COPY INTO bronze_with_newline_arr (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        ARRAY_CONSTRUCT($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        -- 最大カラム数まで $N を列挙（余分なカラムは NULL になるがエラーにはならない）
    FROM @~/test_fk/test_with_comma.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

SELECT inserted_at, raw_data FROM bronze_with_newline_arr;
