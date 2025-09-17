{% macro nx_prefix(type) -%}
  {%- if type == 'event' -%}
    evt
  {%- elif type == 'person' -%}
    per
  {%- elif type == 'group' -%}
    grp
  {%- elif type == 'membership' -%}
    mem
  {%- elif type == 'state' -%}
    st
  {%- elif type == 'person_identifier' -%}
    per_idfr
  {%- elif type == 'group_identifier' -%}
    grp_idfr
  {%- elif type == 'person_trait' -%}
    per_tr
  {%- elif type == 'group_trait' -%}
    grp_tr
  {%- elif type == 'person_edge' -%}
    per_edg
  {%- elif type == 'group_edge' -%}
    grp_edg
  {%- elif type == 'person_participant' -%}
    per_prt
  {%- elif type == 'group_participant' -%}
    grp_prt
  {%- elif type == 'nexus' -%}
    nx
  {%- else -%}
    {{ type[:3] }}
  {%- endif -%}
{%- endmacro %}

{% macro nx_source_token(source) -%}
  {{ source }}
{%- endmacro %}

{% macro nx_sk(cols) -%}
  {{ dbt_utils.generate_surrogate_key(cols) }}
{%- endmacro %}

{% macro create_nexus_id(type, cols, source=None) -%}
  {%- set p = nx_prefix(type) -%}
  {%- if source is none or source == '' -%}
    {{ "'" ~ p ~ "'" }} || '_' || {{ nx_sk(cols) }}
  {%- else -%}
    {{ "'" ~ p ~ "'" }} || '_' || {{ nx_source_token(source) }} || '_' || {{ nx_sk(cols) }}
  {%- endif -%}
{%- endmacro %}