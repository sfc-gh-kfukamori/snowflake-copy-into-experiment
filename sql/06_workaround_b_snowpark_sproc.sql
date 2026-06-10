-- =============================================================
-- 06_workaround_b_snowpark_sproc.sql
-- 回避策B: Snowpark Python ストアドプロシージャによるロード
--
-- 目的:
--   COPY INTO では FIELD_DELIMITER=NONE + FIELD_OPTIONALLY_ENCLOSED_BY の
--   組み合わせで多カラムCSVのフィールド内改行を処理できない問題を回避するため、
--   Python の csv.DictReader を使って正しくパースしてから VARIANT 型にロードする。
--
-- 特徴:
--   - ファイル名の指定不要。ステージ内の全ファイルを自動検出して処理する。
--   - SPROC_LOAD_HISTORY テーブルでロード済みファイルを管理し、未ロードのみ処理。
--   - ファイルごとにエラーが発生しても次のファイルへ処理を継続する。
--
-- ファイルアップロード（Python コネクタ推奨）:
--   python3 -c "
--   import snowflake.connector
--   conn = snowflake.connector.connect(connection_name='K_FUKAMORI')
--   cur = conn.cursor()
--   for f in ['test_with_comma.csv', 'test_no_comma.csv', 'test_with_header.csv']:
--       cur.execute(f'PUT file:///path/to/data/{f} @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE')
--   conn.close()
--   "
-- =============================================================

USE DATABASE CSV_EXPERIMENT_DB;
USE SCHEMA PUBLIC;

-- ---------------------------------------------------------------
-- 1. ロード履歴テーブル
--    ロード済みファイルを管理し、再実行時の二重ロードを防ぐ
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE SPROC_LOAD_HISTORY (
    stage_name    VARCHAR,
    file_name     VARCHAR,
    target_table  VARCHAR,
    loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    row_count     INT,
    status        VARCHAR        -- 'SUCCESS' or 'ERROR: <message>'
);


-- ---------------------------------------------------------------
-- 2. ターゲットテーブル
-- ---------------------------------------------------------------
CREATE OR REPLACE TABLE test_snowpark_load (
    inserted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_data    VARIANT
);


-- ---------------------------------------------------------------
-- 3. ストアドプロシージャ
--    引数: stage_name, target_table のみ（ファイル名指定不要）
--
--    処理フロー:
--      1. LIST でステージ内の全ファイルを取得
--      2. SPROC_LOAD_HISTORY で未ロードファイルを絞り込む
--      3. 未ロードファイルを順次処理:
--         a. BUILD_SCOPED_FILE_URL でスコープ付きURLを生成
--         b. SnowflakeFile.open でファイルを読み込む（str型で返る）
--         c. csv.DictReader でパース（フィールド内改行に対応）
--         d. PARSE_JSON で VARIANT 型に変換してターゲットテーブルに書き込み
--         e. 履歴テーブルに結果を記録
--      4. エラーが発生しても次のファイルへ続行
--
--    注意: ストアドプロシージャ内でのファイル読み込み
--      NG: session.file.get_stream(stage_path)
--      NG: SnowflakeFile.open(stage_path, require_scoped_url=False)
--      OK: BUILD_SCOPED_FILE_URL + SnowflakeFile.open(scoped_url)
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE load_csv_as_variant(
    stage_name   VARCHAR,   -- 例: '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage'
    target_table VARCHAR    -- 例: 'CSV_EXPERIMENT_DB.PUBLIC.test_snowpark_load'
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

HISTORY_TABLE = 'CSV_EXPERIMENT_DB.PUBLIC.SPROC_LOAD_HISTORY'

def run(session, stage_name: str, target_table: str) -> str:
    try:
        # ステージ内のファイル一覧を取得
        # LIST の name 列は "stagename/relative/path.csv" 形式
        stage_files = session.sql(f"LIST {stage_name}").collect()
        if not stage_files:
            return 'OK: No files in stage'

        # 相対パスを抽出（先頭の "stagename/" を除去）
        all_files = ['/'.join(row[0].split('/')[1:]) for row in stage_files]

        # ロード済みファイルを取得
        loaded_rows = session.sql(f"""
            SELECT file_name FROM {HISTORY_TABLE}
            WHERE stage_name   = '{stage_name}'
              AND target_table = '{target_table}'
              AND status       = 'SUCCESS'
        """).collect()
        loaded_files = {row[0] for row in loaded_rows}

        # 未ロードファイルのみ処理
        pending_files = [f for f in all_files if f not in loaded_files]

        if not pending_files:
            return (
                f'OK: No new files to process '
                f'(all {len(all_files)} file(s) already loaded)'
            )

        total_rows = 0
        results = []

        for file_name in pending_files:
            try:
                # スコープ付きURLを生成
                scoped_url = session.sql(
                    f"SELECT BUILD_SCOPED_FILE_URL('{stage_name}', '{file_name}')"
                ).collect()[0][0]

                # ファイルを読み込む
                with SnowflakeFile.open(scoped_url, 'r') as f:
                    content = f.read()

                # csv.DictReader でパース（フィールド内改行に対応）
                reader = csv.DictReader(io.StringIO(content))
                rows_json = [json.dumps(dict(row), ensure_ascii=False) for row in reader]
                row_count = len(rows_json)

                if rows_json:
                    df = session.create_dataframe(
                        [[r] for r in rows_json], schema=['raw_json']
                    )
                    df.select(
                        current_timestamp().alias('inserted_at'),
                        parse_json(col('raw_json')).alias('raw_data')
                    ).write.mode('append').save_as_table(target_table)

                # 履歴に記録（SUCCESS）
                session.sql(f"""
                    INSERT INTO {HISTORY_TABLE}
                        (stage_name, file_name, target_table, row_count, status)
                    VALUES
                        ('{stage_name}', '{file_name}', '{target_table}',
                         {row_count}, 'SUCCESS')
                """).collect()

                total_rows += row_count
                results.append(f'  {file_name}: {row_count} rows -> SUCCESS')

            except Exception as file_err:
                err_msg = str(file_err).replace("'", "''")[:500]
                session.sql(f"""
                    INSERT INTO {HISTORY_TABLE}
                        (stage_name, file_name, target_table, row_count, status)
                    VALUES
                        ('{stage_name}', '{file_name}', '{target_table}',
                         0, 'ERROR: {err_msg}')
                """).collect()
                results.append(f'  {file_name}: ERROR - {str(file_err)}')

        success_count = sum(1 for r in results if 'SUCCESS' in r)
        summary = (
            f'OK: {total_rows} rows loaded from '
            f'{success_count}/{len(pending_files)} file(s)'
        )
        return summary + '\n' + '\n'.join(results)

    except Exception as e:
        return f'ERROR: {str(e)}'
$$;


-- ---------------------------------------------------------------
-- 4. 実行（ファイル名指定不要）
-- ---------------------------------------------------------------
CALL load_csv_as_variant(
    '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage',
    'CSV_EXPERIMENT_DB.PUBLIC.test_snowpark_load'
);
-- 期待する出力例:
-- OK: 2 rows loaded from 1/1 file(s)
--   test_with_header.csv: 2 rows -> SUCCESS
--
-- 2回目以降の実行:
-- OK: No new files to process (all 1 file(s) already loaded)


-- ---------------------------------------------------------------
-- 5. 結果確認
-- ---------------------------------------------------------------
SELECT COUNT(*) AS row_count FROM test_snowpark_load;

SELECT
    inserted_at,
    raw_data,
    raw_data:col1::VARCHAR                        AS col1,
    raw_data:col2::VARCHAR                        AS col2,
    raw_data:col3::VARCHAR                        AS col3,
    CONTAINS(raw_data:col1::VARCHAR, '\n')         AS col1_has_newline,
    REPLACE(raw_data:col1::VARCHAR, '\n', '[LF]') AS col1_visible
FROM test_snowpark_load
ORDER BY inserted_at;

-- ロード履歴の確認
SELECT * FROM SPROC_LOAD_HISTORY ORDER BY loaded_at;
