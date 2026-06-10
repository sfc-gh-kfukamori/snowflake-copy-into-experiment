# Snowflake COPY INTO: FIELD_DELIMITER=NONE と FIELD_OPTIONALLY_ENCLOSED_BY の挙動検証

## 概要

SnowflakeのCOPY INTOコマンドにおいて、`FIELD_DELIMITER = NONE` と `FIELD_OPTIONALLY_ENCLOSED_BY` を併用した場合の挙動を実機で検証した結果をまとめる。

**検証の動機**: セル内に改行コードを含むCSVファイルを、1レコード丸ごとVARIANT型の1カラムに取り込む要件に対して、`FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY` の組み合わせが有効かどうかが不明であったため。

---

## ディレクトリ構成

```
snowflake-copy-into-experiment/
├── README.md
├── data/
│   ├── test_with_comma.csv       # フィールド内改行あり・カンマあり（ヘッダーなし）
│   ├── test_no_comma.csv         # フィールド内改行あり・カンマなし（1カラムCSV）
│   ├── test_with_header.csv      # フィールド内改行あり・カンマあり・ヘッダーあり（回避策B用）
│   └── test_products.csv         # 回避策B 動作確認用（異なるスキーマ・複数行にまたがる改行）
└── sql/
    ├── 00_setup.sql                              # 実験環境のセットアップ
    ├── 01_case1_field_delimiter_none_only.sql    # Case 1: FIELD_DELIMITER=NONE のみ
    ├── 02_case2_field_delimiter_none_with_enclosed.sql  # Case 2: FIELD_DELIMITER=NONE + FIELD_OPTIONALLY_ENCLOSED_BY
    ├── 03_case3_normal_csv.sql                   # Case 3: 正常系（比較用）
    ├── 04_case4_no_comma_with_enclosed.sql       # Case 4: カンマなしCSV + FIELD_OPTIONALLY_ENCLOSED_BY
    ├── 05_variant_load_patterns.sql              # 参考: VARIANT型ロードパターン集
    └── 06_workaround_b_snowpark_sproc.sql        # 回避策B: Snowpark Python ストアドプロシージャ
```

---

## テストデータ

### test_with_comma.csv（フィールド内改行あり・カンマあり・ヘッダーなし）

```
"aaa
bbb",ccc,ddd
eee,fff,ggg
```

バイト列: `b'"aaa\nbbb",ccc,ddd\neee,fff,ggg\n'`

- 1レコード目: `"aaa\nbbb"` はダブルクォーテーションで囲まれた、改行コードを含む1フィールド
- 2レコード目: 通常のCSVレコード

### test_no_comma.csv（フィールド内改行あり・カンマなし）

```
"aaa
bbb"
eee
```

バイト列: `b'"aaa\nbbb"\neee\n'`

- 1レコード目: ダブルクォーテーションで囲まれた、改行コードを含む単一フィールド
- 2レコード目: 通常のフィールド

### test_with_header.csv（フィールド内改行あり・カンマあり・ヘッダーあり）

```
col1,col2,col3
"aaa
bbb",ccc,ddd
eee,fff,ggg
```

バイト列: `b'col1,col2,col3\n"aaa\nbbb",ccc,ddd\neee,fff,ggg\n'`

- 1行目: ヘッダー行（`csv.DictReader` がキーとして使用）
- 2レコード目: `col1` にフィールド内改行を含むレコード
- 3レコード目: 通常のレコード

### test_products.csv（回避策B 動作確認用・異なるスキーマ）

```
id,name,description,category
1,Product A,"高品質アイテム
屋外使用に最適",Electronics
2,Product B,標準アイテム,Clothing
3,Product C,"複数行の
説明文
3行にまたがる",Food
4,Product D,シンプルな説明,Electronics
```

- ヘッダー: `id, name, description, category`（`test_with_header.csv` とは異なるスキーマ）
- id=1: `description` に1行の改行を含む
- id=2,4: 改行なしの通常フィールド
- id=3: `description` が3行にまたがる改行を含む

---

## 実験環境

| 項目 | 値 |
|------|-----|
| Snowflake接続 | K_FUKAMORI |
| アカウントロケータ | ZX48016 |
| データベース | CSV_EXPERIMENT_DB |
| スキーマ | PUBLIC |
| ステージ | `@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage`（名前付き内部ステージ） |
| Snowflake CLI | 3.15.0 |
| 実験日 | 2026-06-10 |

### ファイルアップロード方法

`snow` CLI のセッショントークンが無効になる場合があるため、Python コネクタを推奨する。

```python
import snowflake.connector

conn = snowflake.connector.connect(connection_name='K_FUKAMORI')
cur = conn.cursor()
for f in ['test_with_comma.csv', 'test_no_comma.csv', 'test_with_header.csv']:
    cur.execute(
        f'PUT file:///path/to/data/{f} '
        '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage '
        'AUTO_COMPRESS=FALSE OVERWRITE=TRUE'
    )
conn.close()
```

---

## 実験結果

### Case 1: `FIELD_DELIMITER = NONE` のみ（test_with_comma.csv）

**テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.CASE1_FIELD_DELIMITER_NONE`

**設定:**
```sql
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
)
```

**結果: 3行ロード（レコードが分断）**

| raw_data | char_length | has_doublequote | visible_newline |
|----------|-------------|-----------------|-----------------|
| `"aaa`   | 4           | TRUE            | `"aaa`          |
| `bbb",ccc,ddd` | 12    | TRUE            | `bbb",ccc,ddd`  |
| `eee,fff,ggg`  | 11    | FALSE           | `eee,fff,ggg`   |

**考察:**
- `FIELD_DELIMITER = NONE` のみでは、クォーティング処理が行われない
- フィールド内の改行コードが `RECORD_DELIMITER = '\n'` として扱われ、レコードが分断される
- ダブルクォーテーションは文字として残る

---

### Case 2: `FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_with_comma.csv）

**テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.CASE2_NONE_WITH_ENCLOSED_BY`（正常ロード分）  
**エラーログ:** `CSV_EXPERIMENT_DB.PUBLIC.CASE2_ERROR_LOG`

**設定:**
```sql
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
```

**結果: エラー発生（ON_ERROR=CONTINUE で1行のみロード）**

エラー内容（`CASE2_ERROR_LOG` に記録）:
```
Found character ',' instead of record delimiter '\n'
  File '...test_with_comma.csv', line 2, character 5
```

`ON_ERROR = CONTINUE` 時のロード結果（`CASE2_NONE_WITH_ENCLOSED_BY`）:

| raw_data | char_length | has_doublequote | load_note |
|----------|-------------|-----------------|-----------|
| `eee,fff,ggg` | 11 | FALSE | 行2のみロード成功。行1はエラースキップ |

**考察:**
- `FIELD_OPTIONALLY_ENCLOSED_BY` は `FIELD_DELIMITER = NONE` でも**有効**（調査結果の「無効化される可能性が高い」という推測は誤り）
- パーサーは `"aaa\nbbb"` を正しくクォートフィールドと認識しフィールド内改行を処理する
- しかし `FIELD_DELIMITER = NONE` の場合、クォートフィールドの後に「レコード区切り文字 `\n`」を期待するが、実際には `,ccc,ddd` が続くためエラーになる
- エラーの原因は「FIELD_OPTIONALLY_ENCLOSED_BY が無効」ではなく「FIELD_DELIMITER=NONE なのにクォート後にフィールドが続いている」こと

---

### Case 3: `FIELD_DELIMITER = ','` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_with_comma.csv）

**テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.CASE3_NORMAL_CSV`

**設定:**
```sql
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
```

**結果: 2行ロード（期待通り）**

| c1 | c2 | c3 | c1_length | c1_has_newline | c1_visible |
|----|----|----|-----------|----------------|------------|
| `aaa\nbbb` | `ccc` | `ddd` | 7 | TRUE | `aaa[LF]bbb` |
| `eee` | `fff` | `ggg` | 3 | FALSE | `eee` |

**考察:**
- `FIELD_DELIMITER = ','` を正しく指定することで、CSVパーサーがフィールド区切りを認識し、クォーティング処理が正常に機能する
- フィールド内の改行コードを含む2カラムCSVが正しく2行にロードされる

---

### Case 4: `FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_no_comma.csv）

**テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.CASE4_NO_COMMA_WITH_ENCLOSED_BY`

**設定:**
```sql
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
```

**結果: 2行ロード（期待通り）**

| raw_data | char_length | has_doublequote | has_newline | visible_newline |
|----------|-------------|-----------------|-------------|-----------------|
| `aaa\nbbb` | 7         | FALSE           | TRUE        | `aaa[LF]bbb`    |
| `eee`      | 3         | FALSE           | FALSE       | `eee`           |

**考察:**
- カンマ（フィールド区切り文字）がないCSVでは、`FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` の組み合わせが正常に機能する
- `FIELD_OPTIONALLY_ENCLOSED_BY` がクォートを認識してストリップし、フィールド内の改行コードを保持したまま1フィールドとしてロードする

---

## 結果サマリー

| Case | テーブル | FIELD_DELIMITER | FIELD_OPTIONALLY_ENCLOSED_BY | ロード行数 | 結果 |
|------|---------|-----------------|------------------------------|-----------|------|
| 1 | `CASE1_FIELD_DELIMITER_NONE` | `NONE` | なし | **3行** | フィールド内改行でレコード分断 |
| 2 | `CASE2_NONE_WITH_ENCLOSED_BY` | `NONE` | `'"'` | **エラー**（ON_ERROR=CONTINUEで1行） | FIELD_OPTIONALLY_ENCLOSED_BYは有効だが、クォート後の`,ccc,ddd`でエラー |
| 3 | `CASE3_NORMAL_CSV` | `','` | `'"'` | **2行** | 正常動作（比較用） |
| 4 | `CASE4_NO_COMMA_WITH_ENCLOSED_BY` | `NONE` | `'"'` | **2行** | カンマなしなら正常動作 |

---

## 重要な発見

### `FIELD_OPTIONALLY_ENCLOSED_BY` は `FIELD_DELIMITER = NONE` でも有効

従来の推測（「FIELD_DELIMITER = NONE ではクォーティング処理が無効化される可能性が高い」）は**誤り**であることが実機確認で判明した。

`FIELD_OPTIONALLY_ENCLOSED_BY` は `FIELD_DELIMITER = NONE` の場合でも機能し、クォートで囲まれたフィールド内の改行コードを正しく処理する。

### エラーの本質的な原因

Case 2 のエラーは「FIELD_OPTIONALLY_ENCLOSED_BY が無効」ではなく、以下の論理的な矛盾から発生する：

1. `FIELD_DELIMITER = NONE` → 「1行 = 1フィールド」として解釈される
2. `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` → `"aaa\nbbb"` を1つのフィールドとして認識する（フィールド内改行も処理される）
3. クォートフィールドの終了後、パーサーは「レコード区切り文字 `\n`」を期待する
4. しかし実際には `,ccc,ddd` が続くため、「`,` はレコード区切りでない」としてエラーになる

### 適用可能なケース

`FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` が機能するのは、**各行が1つのフィールド（カンマ等の区切り文字を含まない）で構成されるCSV**に限られる。

---

## 要件への適用可否

「セル内に改行コードを含むCSVの1レコードを丸ごとVARIANT型の1カラムに取り込みたい」という要件に対する結論：

| 条件 | `FIELD_DELIMITER=NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY='"'` | 推奨アプローチ |
|------|-------------------------------------------------------------|--------------|
| フィールド内改行なし | **OK** | `FIELD_DELIMITER=NONE` + `TO_VARIANT($1)` |
| フィールド内改行あり・カンマなし（1カラムCSV） | **OK** | `FIELD_DELIMITER=NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY='"'` + `TO_VARIANT($1)` |
| フィールド内改行あり・カンマあり（多カラムCSV） | **NG（エラー）** | 下記いずれかの回避策を参照 |

**多カラムCSVかつフィールド内改行ありの場合**、COPY INTO の `FIELD_DELIMITER = NONE` で1行丸ごと取り込む方法はCSVスキーマ変更に自動追従できるが、フィールド内改行を正しく処理できない。以下いずれかの対応が必要：

1. **`OBJECT_CONSTRUCT` 方式**: カラム名と数が既知の場合。スキーマ変更時にSQL修正が必要。
2. **`ARRAY_CONSTRUCT` 方式**: カラム名が不要で最大カラム数が見積もれる場合。余分カラムはNULLになる。
3. **前処理方式**: フィールド内改行を別文字に置換してからロード。忠実性は損なわれる。
4. **Snowpark Python ストアドプロシージャ方式（回避策B）**: スキーマ変更に完全自動追従。詳細は下記セクションを参照。

---

## 回避策B: Snowpark Python ストアドプロシージャ（実験結果）

### 概要

COPY INTO では解決できない「フィールド内改行あり・多カラムCSV → 1レコード丸ごとVARIANT」の問題を、Snowpark Python の `csv.DictReader` を使って解決する。

**特徴:**
- **ファイル名指定不要** — `LIST` でステージ内の全ファイルを自動検出
- **重複ロード防止** — `SPROC_LOAD_HISTORY` テーブルでロード済みファイルを管理し、未ロードのみ処理
- **エラー耐性** — 1ファイルが失敗しても次のファイルへ処理を継続し、結果を履歴に記録
- **スキーマ変更への自動追従** — `csv.DictReader` がヘッダー行をキーとして読み取るため、カラム追加・削除時もプロシージャの変更不要

### 呼び出し方（引数2つのみ）

```sql
-- ステージ名とターゲットテーブル名だけ指定する
-- ステージ内の未ロードファイルが自動的に全件処理される
CALL load_csv_as_variant(
    '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage',
    'CSV_EXPERIMENT_DB.PUBLIC.test_snowpark_load'
);
```

### 実装

```sql
CREATE OR REPLACE PROCEDURE load_csv_as_variant(
    stage_name   VARCHAR,   -- '@CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage'
    target_table VARCHAR    -- 'CSV_EXPERIMENT_DB.PUBLIC.test_snowpark_load'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
import csv, io, json
from snowflake.snowpark.files import SnowflakeFile
from snowflake.snowpark.functions import parse_json, current_timestamp, col

HISTORY_TABLE = 'CSV_EXPERIMENT_DB.PUBLIC.SPROC_LOAD_HISTORY'

def run(session, stage_name: str, target_table: str) -> str:
    try:
        # ステージ内のファイル一覧を取得
        stage_files = session.sql(f"LIST {stage_name}").collect()
        if not stage_files:
            return 'OK: No files in stage'

        # 相対パスを抽出（LIST出力: "stagename/file.csv" → "file.csv"）
        all_files = ['/'.join(row[0].split('/')[1:]) for row in stage_files]

        # ロード済みファイルを取得
        loaded_files = {
            row[0] for row in session.sql(f"""
                SELECT file_name FROM {HISTORY_TABLE}
                WHERE stage_name = '{stage_name}'
                  AND target_table = '{target_table}'
                  AND status = 'SUCCESS'
            """).collect()
        }

        pending_files = [f for f in all_files if f not in loaded_files]
        if not pending_files:
            return f'OK: No new files to process (all {len(all_files)} file(s) already loaded)'

        total_rows, results = 0, []

        for file_name in pending_files:
            try:
                scoped_url = session.sql(
                    f"SELECT BUILD_SCOPED_FILE_URL('{stage_name}', '{file_name}')"
                ).collect()[0][0]

                with SnowflakeFile.open(scoped_url, 'r') as f:
                    content = f.read()

                reader = csv.DictReader(io.StringIO(content))
                rows_json = [json.dumps(dict(row), ensure_ascii=False) for row in reader]
                row_count = len(rows_json)

                if rows_json:
                    df = session.create_dataframe([[r] for r in rows_json], schema=['raw_json'])
                    df.select(
                        current_timestamp().alias('inserted_at'),
                        parse_json(col('raw_json')).alias('raw_data')
                    ).write.mode('append').save_as_table(target_table)

                session.sql(f"""
                    INSERT INTO {HISTORY_TABLE}
                        (stage_name, file_name, target_table, row_count, status)
                    VALUES ('{stage_name}', '{file_name}', '{target_table}', {row_count}, 'SUCCESS')
                """).collect()
                total_rows += row_count
                results.append(f'  {file_name}: {row_count} rows -> SUCCESS')

            except Exception as e:
                err = str(e).replace("'", "''")[:500]
                session.sql(f"""
                    INSERT INTO {HISTORY_TABLE}
                        (stage_name, file_name, target_table, row_count, status)
                    VALUES ('{stage_name}', '{file_name}', '{target_table}', 0, 'ERROR: {err}')
                """).collect()
                results.append(f'  {file_name}: ERROR - {str(e)}')

        success_count = sum(1 for r in results if 'SUCCESS' in r)
        return (
            f'OK: {total_rows} rows loaded from {success_count}/{len(pending_files)} file(s)\n'
            + '\n'.join(results)
        )
    except Exception as e:
        return f'ERROR: {str(e)}'
$$;
```

### 実験結果

**テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.TEST_SNOWPARK_LOAD`  
**履歴テーブル:** `CSV_EXPERIMENT_DB.PUBLIC.SPROC_LOAD_HISTORY`

**1回目の実行（ステージ内3ファイルを一括処理）:**
```
OK: 4 rows loaded from 3/3 file(s)
  test_no_comma.csv: 1 rows -> SUCCESS
  test_with_comma.csv: 1 rows -> SUCCESS
  test_with_header.csv: 2 rows -> SUCCESS
```

**2回目の実行（全ファイルがロード済みのためスキップ）:**
```
OK: No new files to process (all 3 file(s) already loaded)
```

**SPROC_LOAD_HISTORY の内容:**

| stage_name | file_name | target_table | row_count | status |
|------------|-----------|--------------|-----------|--------|
| @CSV_EXPERIMENT_DB... | test_no_comma.csv | CSV_EXPERIMENT_DB... | 1 | SUCCESS |
| @CSV_EXPERIMENT_DB... | test_with_comma.csv | CSV_EXPERIMENT_DB... | 1 | SUCCESS |
| @CSV_EXPERIMENT_DB... | test_with_header.csv | CSV_EXPERIMENT_DB... | 2 | SUCCESS |

- `col1` に `aaa\nbbb`（7文字・改行込み）が正しく保持された
- ダブルクォーテーションはストリップされ、フィールド値のみが格納された
- `raw_data` は `{"col1": "aaa\nbbb", "col2": "ccc", "col3": "ddd"}` のようなVARIANT型JSONとして格納

### 実装上の注意点

ストアドプロシージャ内でのファイル読み込み方法には制限がある：

| 方法 | 結果 | 備考 |
|------|------|------|
| `session.file.get_stream(stage_path)` | **NG** | ストアドプロシージャ内では動作しない |
| `SnowflakeFile.open(stage_path, require_scoped_url=False)` | **NG** | 同上 |
| `BUILD_SCOPED_FILE_URL` + `SnowflakeFile.open(scoped_url)` | **OK** | スコープ付きURLを経由することで読み込める |

また、`SnowflakeFile.open` は `str` 型を返すため `.decode()` は不要。

### スキーマ変更への追従

`csv.DictReader` はヘッダー行を自動的にキーとして読み取るため、CSVにカラムが追加・削除されてもプロシージャのコード変更は不要。新カラムは自動的に VARIANT の新キーとして取り込まれる。

---

### 追加検証: 新規ファイル（test_products.csv）での動作確認

`test_with_header.csv` とは異なるスキーマ（`id, name, description, category`）・3行にまたがるフィールド内改行を含む `test_products.csv` を追加してプロシージャを再実行し、以下を検証した。

**実行結果:**
```
OK: 4 rows loaded from 1/1 file(s)
  test_products.csv: 4 rows -> SUCCESS
```

- ステージ内の4ファイルのうち、既ロード済み3ファイル（`test_no_comma.csv`, `test_with_comma.csv`, `test_with_header.csv`）は**スキップ**
- 新規1ファイルのみが処理された（重複ロード防止の動作を確認）

**ロード結果の詳細（`TEST_SNOWPARK_LOAD` より）:**

| id | name | category | desc_length | desc_has_newline | desc_visible |
|----|------|----------|-------------|------------------|--------------|
| 1 | Product A | Electronics | 15 | **True** | `高品質アイテム[LF]屋外使用に最適` |
| 2 | Product B | Clothing | 6 | False | `標準アイテム` |
| 3 | Product C | Food | 16 | **True** | `複数行の[LF]説明文[LF]3行にまたがる` |
| 4 | Product D | Electronics | 7 | False | `シンプルな説明` |

**確認できたこと:**

| 検証項目 | 結果 |
|---------|------|
| 既存3ファイルのスキップ | ✅ 新規1ファイルのみ処理 |
| 異なるスキーマへの自動追従 | ✅ `id, name, description, category` を自動認識 |
| 1行の改行（id=1） | ✅ `高品質アイテム[LF]屋外使用に最適`（15文字） |
| 3行にまたがる改行（id=3） | ✅ `複数行の[LF]説明文[LF]3行にまたがる`（16文字） |
| 改行なし通常フィールド（id=2,4） | ✅ そのまま格納 |
| 履歴への記録 | ✅ `SPROC_LOAD_HISTORY` に4件目として追記 |

**`SPROC_LOAD_HISTORY` 最終状態（全4ファイル）:**

| file_name | row_count | status |
|-----------|-----------|--------|
| test_no_comma.csv | 1 | SUCCESS |
| test_with_comma.csv | 1 | SUCCESS |
| test_with_header.csv | 2 | SUCCESS |
| test_products.csv | 4 | SUCCESS |

---

## Snowflakeオブジェクト一覧（CSV_EXPERIMENT_DB.PUBLIC）

| オブジェクト名 | 種別 | 説明 |
|--------------|------|------|
| `csv_load_stage` | ステージ | テスト用CSVファイル格納先 |
| `CASE1_FIELD_DELIMITER_NONE` | テーブル | Case 1 実験結果（3行） |
| `CASE2_NONE_WITH_ENCLOSED_BY` | テーブル | Case 2 ロード結果（1行・エラースキップ後） |
| `CASE2_ERROR_LOG` | テーブル | Case 2 エラー内容の記録 |
| `CASE3_NORMAL_CSV` | テーブル | Case 3 実験結果（2行） |
| `CASE4_NO_COMMA_WITH_ENCLOSED_BY` | テーブル | Case 4 実験結果（2行） |
| `TEST_SNOWPARK_LOAD` | テーブル | 回避策B 実験結果（VARIANT型） |
| `SPROC_LOAD_HISTORY` | テーブル | 回避策B ロード履歴（重複ロード防止用） |
| `LOAD_CSV_AS_VARIANT` | ストアドプロシージャ | 回避策B 実装（引数: stage_name, target_table） |

---

## 参考: VARIANT型ロードSQLパターン

`sql/05_variant_load_patterns.sql` に実用的なパターンをまとめている。

```sql
-- パターンB（推奨）: フィールド内改行あり → OBJECT_CONSTRUCT
COPY INTO bronze_logs (inserted_at, raw_data)
FROM (
    SELECT
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT('c1', $1, 'c2', $2, 'c3', $3)
    FROM @CSV_EXPERIMENT_DB.PUBLIC.csv_load_stage/logs/
)
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ESCAPE_UNENCLOSED_FIELD = NONE
    NULL_IF = ('')
);
```

---

## 公式リファレンス

| トピック | URL |
|---------|-----|
| COPY INTO \<table\> | https://docs.snowflake.com/en/sql-reference/sql/copy-into-table |
| CREATE FILE FORMAT (CSV オプション) | https://docs.snowflake.com/en/sql-reference/sql/create-file-format |
| TO_VARIANT 関数 | https://docs.snowflake.com/en/sql-reference/functions/to_variant |
| OBJECT_CONSTRUCT 関数 | https://docs.snowflake.com/en/sql-reference/functions/object_construct |
| ARRAY_CONSTRUCT 関数 | https://docs.snowflake.com/en/sql-reference/functions/array_construct |
| Snowpark Python ストアドプロシージャ | https://docs.snowflake.com/en/developer-guide/snowpark/python/creating-sprocs |
| SnowflakeFile (ファイルアクセスAPI) | https://docs.snowflake.com/en/developer-guide/snowpark/python/udf-python-read-files |
| BUILD_SCOPED_FILE_URL 関数 | https://docs.snowflake.com/en/sql-reference/functions/build_scoped_file_url |
