-- =============================================================
-- 07_case5_object_construct.sql
-- Case 5: OBJECT_CONSTRUCT パターン
--
-- 目的:
--   FIELD_DELIMITER=',' + FIELD_OPTIONALLY_ENCLOSED_BY='"' で
--   フィールド内改行を正しくパースし、OBJECT_CONSTRUCT で
--   各フィールドを JSON オブジェクトとして VARIANT 型にロードする。
--
-- 特徴:
--   - 純粋な SQL で実装可能（Snowpark 不要）
--   - カラム名を明示的に指定するため可読性が高い
--   - カラム数・カラム名が変わった場合は SQL の修正が必要
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------
-- Case 5a: test_with_header.csv（3カラム: col1, col2, col3）
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE CASE5A_OBJECT_CONSTRUCT_HEADER (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

COPY INTO CASE5A_OBJECT_CONSTRUCT_HEADER (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT('col1', $1, 'col2', $2, 'col3', $3)
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_with_header.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
);

SELECT
    raw_data,
    raw_data:col1::VARCHAR                        AS col1,
    raw_data:col2::VARCHAR                        AS col2,
    raw_data:col3::VARCHAR                        AS col3,
    LENGTH(raw_data:col1::VARCHAR)                AS col1_length,
    CONTAINS(raw_data:col1::VARCHAR, '\n')         AS col1_has_newline,
    REPLACE(raw_data:col1::VARCHAR, '\n', '[LF]') AS col1_visible
FROM CASE5A_OBJECT_CONSTRUCT_HEADER;

-- 期待する出力:
-- 行1: col1 = "aaa\nbbb"（7文字・改行込み）, col2 = "ccc", col3 = "ddd"
-- 行2: col1 = "eee", col2 = "fff", col3 = "ggg"


-- ---------------------------------------------------------------
-- Case 5b: test_products.csv（4カラム: id, name, description, category）
--          description に1行・3行にまたがるフィールド内改行を含む
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE CASE5B_OBJECT_CONSTRUCT_PRODUCTS (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

COPY INTO CASE5B_OBJECT_CONSTRUCT_PRODUCTS (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT('id', $1, 'name', $2, 'description', $3, 'category', $4)
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_products.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
);

SELECT
    raw_data:id::INT                                     AS id,
    raw_data:name::VARCHAR                               AS name,
    raw_data:category::VARCHAR                           AS category,
    LENGTH(raw_data:description::VARCHAR)                AS desc_length,
    CONTAINS(raw_data:description::VARCHAR, '\n')         AS desc_has_newline,
    REPLACE(raw_data:description::VARCHAR, '\n', '[LF]') AS desc_visible
FROM CASE5B_OBJECT_CONSTRUCT_PRODUCTS
ORDER BY raw_data:id::INT;

-- 期待する出力:
-- id=1: description に改行1行（高品質アイテム[LF]屋外使用に最適）
-- id=2: 改行なし
-- id=3: description に改行3行（複数行の[LF]説明文[LF]3行にまたがる）
-- id=4: 改行なし


-- ---------------------------------------------------------------
-- Case 5c: スキーマ変更時の挙動確認（OBJECT_CONSTRUCT の制限）
--          test_products_v2.csv: price カラムが追加された5カラムCSV
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE CASE5C_SCHEMA_CHANGE_OBJECT_CONSTRUCT (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);

-- 旧スキーマ（4カラム）のSQL のまま新ファイル（5カラム）を処理
-- → price ($5) が OBJECT_CONSTRUCT に含まれないため欠落する
COPY INTO CASE5C_SCHEMA_CHANGE_OBJECT_CONSTRUCT (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT('id', $1, 'name', $2, 'description', $3, 'category', $4)
        -- ← $5 (price) が抜けている！スキーマ変更時はここに追加が必要
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/test_products_v2.csv
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
);

-- price が NULL になることを確認
SELECT
    raw_data:id::INT       AS id,
    raw_data:name::VARCHAR AS name,
    raw_data:price         AS price   -- NULL になる
FROM CASE5C_SCHEMA_CHANGE_OBJECT_CONSTRUCT
ORDER BY raw_data:id::INT;

-- ▼ SQL を修正すれば price も取り込める
-- OBJECT_CONSTRUCT('id', $1, 'name', $2, 'description', $3, 'category', $4, 'price', $5)

-- ---------------------------------------------------------------
-- 【比較】Snowpark ストアドプロシージャは SQL 修正不要
-- ---------------------------------------------------------------
-- CALL load_csv_as_variant(
--     '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage',
--     'CSV_EXPERIMENT_DB.PUBLIC.test_snowpark_load'
-- );
-- → test_products_v2.csv が未ロードであれば自動検出・price も含めて取り込まれる
