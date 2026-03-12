{% macro format_anomaly(monitor_name, granularity, date_column, dimension_columns, measure_columns) %}
{#
  Normalizes a scored anomaly query's output into the generic nexus_anomaly_detections schema.
  
  Call this in the final SELECT of a monitoring model to pack dimension/measure columns 
  into the standard JSON format.

  Args:
    monitor_name: string identifier for this monitor
    granularity: 'daily', 'weekly', 'monthly', or none for cross-sectional
    date_column: the name of the date column (or none for cross-sectional)
    dimension_columns: list of dimension column names (excluding the date column)
    measure_columns: list of measure column names (z-score columns are inferred as {name}_z)
#}

    {{ nexus.create_nexus_id('detection', [
        "'" ~ monitor_name ~ "'",
        'dimension_key',
        date_column if date_column else "'_cross_sectional'"
    ]) }} as detection_id,

    '{{ monitor_name }}' as monitor_name,
    current_timestamp() as detected_at,
    dimension_key,

    {% if date_column %}
    {{ date_column }}::timestamp as occurred_at,
    '{{ granularity }}' as granularity,
    {% else %}
    cast(null as timestamp) as occurred_at,
    cast(null as varchar) as granularity,
    {% endif %}

    {% if target.type == 'snowflake' %}
    object_construct(
        {% for col in dimension_columns %}
        '{{ col }}', {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    ) as dimensions,
    object_construct(
        {% for col in measure_columns %}
        '{{ col }}', {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    ) as measures,
    object_construct(
        {% for col in measure_columns %}
        '{{ col }}_z', {{ col }}_z{{ ',' if not loop.last }}
        {% endfor %}
    ) as z_scores,
    {% else %}
    struct(
        {% for col in dimension_columns %}
        {{ col }} as {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    ) as dimensions,
    struct(
        {% for col in measure_columns %}
        {{ col }} as {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    ) as measures,
    struct(
        {% for col in measure_columns %}
        {{ col }}_z as {{ col }}_z{{ ',' if not loop.last }}
        {% endfor %}
    ) as z_scores,
    {% endif %}

    max_abs_z

{% endmacro %}
