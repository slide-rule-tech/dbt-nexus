{# Cross-adapter JSON parsing.

   Snowflake stores parsed JSON as the `VARIANT` type, navigated with
   the `:` operator (`col:a:b::TYPE`). DuckDB uses the `JSON` type with
   `json_extract*` functions and JSONPath strings (`'$.a.b'`). BigQuery
   has `JSON` type with `JSON_VALUE`/`JSON_QUERY`.

   These macros wrap both layers so model SQL stays adapter-agnostic.
#}

{# Parse a text column as JSON / VARIANT.

   Usage:
     select {{ nexus.parse_json('JSON_MESSAGE') }} as payload from ...
     select {{ nexus.parse_json('JSON_MESSAGE', try=true) }} as payload from ...

   `try=true` returns NULL on parse failure rather than raising; matches
   Snowflake's `TRY_PARSE_JSON`. Default is non-try (raise on bad JSON).
#}
{% macro parse_json(column, try=false) %}
{%- if target.type == 'snowflake' -%}
  {%- if try -%}try_parse_json({{ column }}){%- else -%}parse_json({{ column }}){%- endif -%}
{%- elif target.type == 'duckdb' -%}
  {%- if try -%}try_cast({{ column }} as json){%- else -%}cast({{ column }} as json){%- endif -%}
{%- elif target.type == 'bigquery' -%}
  {%- if try -%}safe.parse_json({{ column }}){%- else -%}parse_json({{ column }}){%- endif -%}
{%- else -%}
  {{ exceptions.raise_compiler_error("nexus.parse_json() does not support target.type='" ~ target.type ~ "' yet") }}
{%- endif -%}
{% endmacro %}


{# Extract a value from a parsed-JSON column at a path, with optional
   type cast.

   Usage:
     {{ nexus.json_path('payload', 'analytics_data.pageUrl', 'string') }}
     {{ nexus.json_path('payload', 'event_time', 'bigint') }}
     {{ nexus.json_path('payload', 'event_input.contents') }}     -- no type → raw sub-object
     {{ nexus.json_path('items', '[0].item_name', 'string') }}    -- array index then key
     {{ nexus.json_path('a', 'b[2].c[1].d', 'number') }}          -- nested arrays

   Path is a string of dotted keys with optional `[N]` array indexers.
   Type is one of: string, bigint, int, integer, float, double,
                   boolean, bool, timestamp, date, json (raw),
                   or None / omitted for raw VARIANT/JSON.

   Adapter rendering:
     Snowflake: `{{ column }}:a:b:c::TYPE` (or `[0]:name`, etc.)
     DuckDB:    `json_extract*({{ column }}, '$.a.b.c')::TYPE` (JSONPath)
                 (uses json_extract_string for string output, json_extract
                  otherwise — DuckDB's STRING cast loses quoting)
     BigQuery:  `JSON_VALUE({{ column }}, '$.a.b.c')` for scalars,
                 `JSON_QUERY` for raw sub-objects; cast to SQL type.
#}
{% macro json_path(column, path, type=none) %}
{%- set tokens = nexus._nexus_split_json_path(path) -%}
{%- if target.type == 'snowflake' -%}
  {%- set sf_path -%}
    {%- for tok in tokens -%}
      {%- if tok.kind == 'index' -%}[{{ tok.value }}]{%- else -%}:{{ tok.value }}{%- endif -%}
    {%- endfor -%}
  {%- endset -%}
  {%- set sf_type = nexus._nexus_json_type_to_sf(type) -%}
  {{ column }}{{ sf_path }}{%- if sf_type %}::{{ sf_type }}{%- endif -%}
{%- elif target.type == 'duckdb' -%}
  {%- set duck_path -%}
    '${%- for tok in tokens -%}
      {%- if tok.kind == 'index' -%}[{{ tok.value }}]{%- else -%}.{{ tok.value }}{%- endif -%}
    {%- endfor -%}'
  {%- endset -%}
  {%- set duck_type = nexus._nexus_json_type_to_duck(type) -%}
  {%- if type and type|lower in ['string', 'varchar', 'text'] -%}
    json_extract_string({{ column }}, {{ duck_path }})
  {%- elif duck_type -%}
    {# try_cast (not cast) matches Snowflake VARIANT::TYPE semantics —
       on Snowflake, casting a variant to a non-matching type returns
       NULL silently. DuckDB's plain cast(json_extract(...) as DECIMAL)
       raises on non-numeric values; try_cast preserves NULL behavior. #}
    try_cast(json_extract({{ column }}, {{ duck_path }}) as {{ duck_type }})
  {%- else -%}
    json_extract({{ column }}, {{ duck_path }})
  {%- endif -%}
{%- elif target.type == 'bigquery' -%}
  {%- set bq_path -%}
    '${%- for tok in tokens -%}
      {%- if tok.kind == 'index' -%}[{{ tok.value }}]{%- else -%}.{{ tok.value }}{%- endif -%}
    {%- endfor -%}'
  {%- endset -%}
  {%- if type is none or type|lower == 'json' -%}
    json_query({{ column }}, {{ bq_path }})
  {%- elif type|lower in ['string', 'varchar', 'text'] -%}
    json_value({{ column }}, {{ bq_path }})
  {%- else -%}
    cast(json_value({{ column }}, {{ bq_path }}) as {{ nexus._nexus_json_type_to_bq(type) }})
  {%- endif -%}
{%- else -%}
  {{ exceptions.raise_compiler_error("nexus.json_path() does not support target.type='" ~ target.type ~ "' yet") }}
{%- endif -%}
{% endmacro %}


{# Internal: tokenize a json path string into a list of {kind, value}
   tokens. kind is 'key' or 'index'. Supports paths like "a.b",
   "items[0].name", "[0].x", "a[1][2].b". #}
{% macro _nexus_split_json_path(path) -%}
  {%- set out = [] -%}
  {%- set buf = namespace(v='') -%}
  {%- for ch in path -%}
    {%- if ch == '.' -%}
      {%- if buf.v -%}{%- do out.append({'kind':'key','value':buf.v}) -%}{%- endif -%}
      {%- set buf.v = '' -%}
    {%- elif ch == '[' -%}
      {%- if buf.v -%}{%- do out.append({'kind':'key','value':buf.v}) -%}{%- endif -%}
      {%- set buf.v = '' -%}
    {%- elif ch == ']' -%}
      {%- if buf.v -%}{%- do out.append({'kind':'index','value':buf.v}) -%}{%- endif -%}
      {%- set buf.v = '' -%}
    {%- else -%}
      {%- set buf.v = buf.v ~ ch -%}
    {%- endif -%}
  {%- endfor -%}
  {%- if buf.v -%}{%- do out.append({'kind':'key','value':buf.v}) -%}{%- endif -%}
  {{- return(out) -}}
{%- endmacro %}


{# Internal: normalize the type arg into per-adapter SQL type names.
   Returns empty string when the type should be omitted (raw access). #}
{% macro _nexus_json_type_to_sf(type) -%}
{%- if type is none or type|lower == 'json' -%}{%- elif type|lower in ['string','varchar','text'] -%}string
{%- elif type|lower in ['int','integer'] -%}integer
{%- elif type|lower in ['bigint','long'] -%}bigint
{%- elif type|lower in ['float','double','number'] -%}{{ type|lower }}
{%- elif type|lower in ['boolean','bool'] -%}boolean
{%- elif type|lower in ['timestamp','timestamp_ntz','timestamp_tz','date'] -%}{{ type|lower }}
{%- else -%}{{ type }}{%- endif -%}
{%- endmacro %}

{% macro _nexus_json_type_to_duck(type) -%}
{%- if type is none or type|lower == 'json' -%}{%- elif type|lower in ['string','varchar','text'] -%}varchar
{%- elif type|lower in ['int','integer'] -%}integer
{%- elif type|lower in ['bigint','long'] -%}bigint
{%- elif type|lower in ['float','double'] -%}double
{%- elif type|lower == 'number' -%}decimal(38,0)
{%- elif type|lower in ['boolean','bool'] -%}boolean
{%- elif type|lower in ['timestamp','timestamp_ntz'] -%}timestamp
{%- elif type|lower == 'timestamp_tz' -%}timestamptz
{%- elif type|lower == 'date' -%}date
{%- else -%}{{ type }}{%- endif -%}
{%- endmacro %}

{% macro _nexus_json_type_to_bq(type) -%}
{%- if type|lower in ['string','varchar','text'] -%}string
{%- elif type|lower in ['int','integer','bigint','long'] -%}int64
{%- elif type|lower in ['float','double','number'] -%}float64
{%- elif type|lower in ['boolean','bool'] -%}bool
{%- elif type|lower in ['timestamp','timestamp_ntz','timestamp_tz'] -%}timestamp
{%- elif type|lower == 'date' -%}date
{%- else -%}{{ type }}{%- endif -%}
{%- endmacro %}
