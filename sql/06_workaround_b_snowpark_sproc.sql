-- =============================================================
-- 06_workaround_b_snowpark_sproc.sql
-- 回避策B: Snowpark Python ストアドプロシージャによるロード
--
-- 目的:
--   COPY INTO では FIELD_DELIMITER=NONE + FIELD_OPTIONALLY_ENCLOSED_BY の
--   組み合わせで多カラムCSVのフィールド内改行を処理できない問題を回避するため、
--   Python の csv.DictReader を使って正しくパースしてから VARIANT 型にロードする。
--
-- 前提:
--   - 名前付き内部ステージ csv_load_stage が存在すること
--   - テストCSVファイルがステージにアップロード済みであること
--     snow sql -q "PUT file:///path/to/data/test_with_header.csv
--                  @DEMO.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE" --connection SZ20347
-- =============================================================

USE DATABASE DEMO;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------
-- 1. 名前付きステージ作成
-- ---------------------------------------------------------------
CREATE OR REPLACE STAGE csv_load_stage;


-- ---------------------------------------------------------------
-- 2. ターゲットテーブル作成
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE test_snowpark_load (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);


-- ---------------------------------------------------------------
-- 3. ストアドプロシージャ作成
--    処理フロー:
--      1. BUILD_SCOPED_FILE_URL でスコープ付きURLを生成
--      2. SnowflakeFile.open でファイルを読み込む（str型で返る）
--      3. csv.DictReader でパース（フィールド内改行を正しく処理）
--      4. 各行を JSON 文字列化してDataFrameを作成
--      5. PARSE_JSON で VARIANT 型に変換してターゲットテーブルに書き込み
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE load_csv_as_variant(
    stage_name   VARCHAR,   -- 例: '@DEMO.PUBLIC.csv_load_stage'
    file_name    VARCHAR,   -- 例: 'test_with_header.csv'
    target_table VARCHAR    -- 例: 'DEMO.PUBLIC.test_snowpark_load'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
import csv
import io
import json
from snowflake.snowpark.files import SnowflakeFile
from snowflake.snowpark.functions import parse_json, current_timestamp, col

def run(session, stage_name: str, file_name: str, target_table: str) -> str:
    try:
        # BUILD_SCOPED_FILE_URL でスコープ付きURLを生成（ストアドプロシージャ内での
        # ファイルアクセスには session.file.get_stream ではなくこの方式が必要）
        scoped_url = session.sql(
            f"SELECT BUILD_SCOPED_FILE_URL('{stage_name}', '{file_name}')"
        ).collect()[0][0]

        # SnowflakeFile.open は str 型でコンテンツを返す（decode 不要）
        with SnowflakeFile.open(scoped_url, 'r') as f:
            content = f.read()

        # csv.DictReader: ヘッダー行をキーとして自動認識、フィールド内改行も正しく処理
        reader = csv.DictReader(io.StringIO(content))
        rows_json = [json.dumps(dict(row), ensure_ascii=False) for row in reader]

        if not rows_json:
            return 'OK: 0 rows (file is empty or header only)'

        # DataFrame を作成して VARIANT 型に変換し書き込み
        df = session.create_dataframe([[r] for r in rows_json], schema=['raw_json'])
        df.select(
            current_timestamp().alias('inserted_at'),
            parse_json(col('raw_json')).alias('raw_data')
        ).write.mode('append').save_as_table(target_table)

        return f'OK: {len(rows_json)} rows loaded into {target_table}'
    except Exception as e:
        return f'ERROR: {str(e)}'
$$;


-- ---------------------------------------------------------------
-- 4. 実行
-- ---------------------------------------------------------------
CALL load_csv_as_variant(
    '@DEMO.PUBLIC.csv_load_stage',
    'test_with_header.csv',
    'DEMO.PUBLIC.test_snowpark_load'
);
-- 期待する出力: OK: 2 rows loaded into DEMO.PUBLIC.test_snowpark_load


-- ---------------------------------------------------------------
-- 5. 結果確認
-- ---------------------------------------------------------------
SELECT COUNT(*) AS row_count FROM test_snowpark_load;

SELECT
    inserted_at,
    raw_data,
    raw_data:col1::VARCHAR                          AS col1,
    raw_data:col2::VARCHAR                          AS col2,
    raw_data:col3::VARCHAR                          AS col3,
    LENGTH(raw_data:col1::VARCHAR)                  AS col1_length,
    CONTAINS(raw_data:col1::VARCHAR, '\n')           AS col1_has_newline,
    REPLACE(raw_data:col1::VARCHAR, '\n', '[LF]')   AS col1_visible
FROM test_snowpark_load
ORDER BY inserted_at;

-- 期待する出力:
-- row_count = 2
-- 行1: col1 = "aaa\nbbb"（7文字、改行含む）, col2 = "ccc", col3 = "ddd"
-- 行2: col1 = "eee", col2 = "fff", col3 = "ggg"
-- → csv.DictReader がフィールド内改行を正しく処理できていることを確認
