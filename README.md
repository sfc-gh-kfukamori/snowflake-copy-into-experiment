# Snowflake COPY INTO: FIELD_DELIMITER=NONE と FIELD_OPTIONALLY_ENCLOSED_BY の挙動検証

## 概要

SnowflakeのCOPY INTOコマンドにおいて、`FIELD_DELIMITER = NONE` と `FIELD_OPTIONALLY_ENCLOSED_BY` を併用した場合の挙動を実機で検証した結果をまとめる。

**検証の動機**: セル内に改行コードを含むCSVファイルを、1レコード丸ごとVARIANT型の1カラムに取り込む要件に対して、`FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY` の組み合わせが有効かどうかが不明であったため。

---

## ディレクトリ構成

```
snowflake-copy-into-experiment/
├── README.md                                    # 本ファイル
├── data/
│   ├── test_with_comma.csv                      # フィールド内改行あり・カンマあり（多カラムCSV）
│   └── test_no_comma.csv                        # フィールド内改行あり・カンマなし（1カラムCSV）
└── sql/
    ├── 00_setup.sql                             # 実験環境のセットアップ
    ├── 01_case1_field_delimiter_none_only.sql   # Case 1: FIELD_DELIMITER=NONE のみ
    ├── 02_case2_field_delimiter_none_with_enclosed.sql  # Case 2: FIELD_DELIMITER=NONE + FIELD_OPTIONALLY_ENCLOSED_BY
    ├── 03_case3_normal_csv.sql                  # Case 3: 正常系（比較用）
    ├── 04_case4_no_comma_with_enclosed.sql      # Case 4: カンマなしCSV + FIELD_OPTIONALLY_ENCLOSED_BY
    └── 05_variant_load_patterns.sql             # 参考: VARIANT型ロードパターン集
```

---

## テストデータ

### test_with_comma.csv（フィールド内改行あり・カンマあり）

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

---

## 実験環境

| 項目 | 値 |
|------|-----|
| Snowflake接続 | SZ20347 |
| データベース | DEMO |
| スキーマ | PUBLIC |
| ステージ | `@~/test_fk/`（ユーザーステージ） |
| Snowflake CLI | 3.15.0 |
| 実験日 | 2026-06-10 |

---

## 実験結果

### Case 1: `FIELD_DELIMITER = NONE` のみ（test_with_comma.csv）

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
| `bbb",ccc,ddd` | 13   | TRUE            | `bbb",ccc,ddd`  |
| `eee,fff,ggg`  | 11   | FALSE           | `eee,fff,ggg`   |

**考察:**
- `FIELD_DELIMITER = NONE` のみでは、クォーティング処理が行われない
- フィールド内の改行コードが `RECORD_DELIMITER = '\n'` として扱われ、レコードが分断される
- ダブルクォーテーションは文字として残る

---

### Case 2: `FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_with_comma.csv）

**設定:**
```sql
FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
```

**結果: エラー発生**

```
Error: Found character ',' instead of record delimiter '\n'
  File '@~/test_fk/test_with_comma.csv', line 2, character 5
```

**`ON_ERROR = CONTINUE` を指定した場合の結果: 1行ロード**

| raw_data | 備考 |
|----------|------|
| `eee,fff,ggg` | 1レコード目はエラースキップ、2レコード目のみロード |

**考察:**
- `FIELD_OPTIONALLY_ENCLOSED_BY` は `FIELD_DELIMITER = NONE` でも**有効**である（調査結果の推測「無効化される可能性が高い」は誤り）
- パーサーは `"aaa\nbbb"` を正しくクォートフィールドと認識し、フィールド内改行を処理する
- しかし `FIELD_DELIMITER = NONE` の場合、クォートフィールドの後に「レコード区切り文字 `\n`」を期待するが、実際には `,ccc,ddd` が続くためエラーになる
- エラーの原因は「FIELD_OPTIONALLY_ENCLOSED_BY が無効」ではなく「FIELD_DELIMITER=NONE なのにクォート後にフィールドが続いている」こと

---

### Case 3: `FIELD_DELIMITER = ','` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_with_comma.csv）

比較用の正常系。

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

| c1 | c2 | c3 | c1_length | c1_has_newline |
|----|----|----|-----------|----------------|
| `aaa\nbbb` | `ccc` | `ddd` | 7 | TRUE |
| `eee` | `fff` | `ggg` | 3 | FALSE |

**考察:**
- `FIELD_DELIMITER = ','` を正しく指定することで、CSVパーサーがフィールド区切りを認識し、クォーティング処理が正常に機能する
- フィールド内の改行コードを含む2カラムCSVが正しく2行にロードされる

---

### Case 4: `FIELD_DELIMITER = NONE` + `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`（test_no_comma.csv）

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
- この組み合わせは「1カラムCSV（各行が1つの値）」であれば有効

---

## 結果サマリー

| Case | ファイル | FIELD_DELIMITER | FIELD_OPTIONALLY_ENCLOSED_BY | ロード行数 | 結果 |
|------|----------|-----------------|------------------------------|-----------|------|
| 1 | test_with_comma.csv | `NONE` | なし | **3行** | フィールド内改行でレコード分断 |
| 2 | test_with_comma.csv | `NONE` | `'"'` | **エラー** | FIELD_OPTIONALLY_ENCLOSED_BYは有効だが、クォート後の`,ccc,ddd`でエラー |
| 3 | test_with_comma.csv | `','` | `'"'` | **2行** | 正常動作（比較用） |
| 4 | test_no_comma.csv   | `NONE` | `'"'` | **2行** | カンマなしなら正常動作 |

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
| フィールド内改行あり・カンマあり（多カラムCSV） | **NG（エラー）** | `FIELD_DELIMITER=','` + `FIELD_OPTIONALLY_ENCLOSED_BY='"'` + `OBJECT_CONSTRUCT` or `ARRAY_CONSTRUCT` |

**多カラムCSVかつフィールド内改行ありの場合**、`FIELD_DELIMITER = NONE` で1行丸ごと取り込む方法はCSVスキーマ変更に自動追従できるが、フィールド内改行を正しく処理できない。以下いずれかの対応が必要：

1. **`OBJECT_CONSTRUCT` 方式**: カラム名と数が既知の場合。スキーマ変更時にSQL修正が必要。
2. **`ARRAY_CONSTRUCT` 方式**: カラム名が不要で最大カラム数が見積もれる場合。余分カラムはNULLになる。
3. **前処理方式**: フィールド内改行を別文字に置換してからロード。忠実性は損なわれる。

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
    FROM @my_stage/logs/
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
