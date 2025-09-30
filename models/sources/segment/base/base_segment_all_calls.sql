{% set segment_calls =  ['pages','tracks','identifies'] %}
{% set segment_call_models = [] %}
{% for segment_call in segment_calls %}
{% set segment_call_model =  'base_segment_' + segment_call %}
{% do segment_call_models.append(ref(segment_call_model)) %}
{% endfor %}

with unioned as (
    {{ dbt_utils.union_relations(
        relations=segment_call_models,
        exclude=["_dbt_source_relation"],
        source_column_name="segment_call_model"
        ) 
    }}
)

select 
    *
from  unioned