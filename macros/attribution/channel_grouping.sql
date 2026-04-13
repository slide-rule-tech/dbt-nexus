{% macro channel_grouping_union(groupings) %}
{#
  Generates a UNION ALL query that computes channel groupings from
  nexus_attribution_model_results. Each grouping produces one row per
  attribution result.

  Args:
    groupings: list of dicts, each with:
      - name (string): channel grouping identifier, e.g. 'marketing_channel'
      - expression (string): SQL CASE expression that returns the channel group value

  Usage (in a client model):
    {{ nexus.channel_grouping_union([
        {
          'name': 'marketing_channel',
          'expression': marketing_channel_grouping('source', 'medium', 'attribution_model_name')
        }
    ]) }}
#}
{% for grouping in groupings %}
{% if not loop.first %}UNION ALL{% endif %}
SELECT
    attribution_model_result_id,
    attribution_model_name,
    '{{ grouping.name }}' as channel_grouping_name,
    {{ grouping.expression }} as channel_group
FROM {{ ref('nexus_attribution_model_results') }}
{% endfor %}
{% endmacro %}
