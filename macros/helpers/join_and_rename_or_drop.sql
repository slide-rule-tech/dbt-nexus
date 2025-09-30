{%- macro join_and_rename_or_drop(rename, ref1, ref2, id1, id2, prefix2) -%}
    -- joins two tables, renaming or droping columns from the second table that are not unique
    -- rename = all, rename all columns from the 2nd table
    -- rename = non-unique, rename non-unique columns from the 2nd table
    -- rename = drop, drop non-unique columns from the 2nd table
    -- store the columns from ref1 and ref2 as a list in jinja
    {%- set columns1 = adapter.get_columns_in_relation(ref1) -%}
    {%- set columns2 = adapter.get_columns_in_relation(ref2) -%}
    {%- set unique_cols = [] -%}
    -- store the columns unique to ref2
    {% for col in columns2 %}
        {% if col not in  columns1 %}
            {%- set _ = unique_cols.append(col) -%}
        {% endif %}
    {% endfor %}

    -- select all columns from ref1 and unique columns from ref2
    select
    {% for col in columns1 %}
        table1.{{col.name}} as {{col.name}},
    {% endfor %}
    {% if rename == 'all' %}
        {% for col in columns2 %}
            {% if not loop.last %}
                table2.{{col.name}} as {{prefix2}}{{col.name}},
            {% else %}
                table2.{{col.name}} as {{prefix2}}{{col.name}}
            {% endif %}
        {% endfor %}
    {% elif rename == 'non-unique' %}
        {% for col in columns2 %}
            {% if not loop.last %}
                {% if col in unique_cols %}
                    table2.{{col.name}} as {{col.name}},
                {% else %}
                    table2.{{col.name}} as {{prefix2}}{{col.name}},
                {% endif %}
            {% else %}
                {% if col in unique_cols %}
                    table2.{{col.name}} as {{col.name}}
                {% else %}
                    table2.{{col.name}} as {{prefix2}}{{col.name}}
                {% endif %}
            {% endif %}
        {% endfor %}
    {% else %}
        {% for col in unique_cols %}
            {% if not loop.last %}
            table2.{{col.name}} as {{prefix2}}{{col.name}},
            {% else %}
            table2.{{col.name}} as {{prefix2}}{{col.name}}
            {% endif %}
        {% endfor %}
    {% endif %}
    from
    {{ ref1 }} as table1
    left join
    {{ ref2 }} as table2
        on table1.{{ id1 }} = table2.{{ id2 }}
{%- endmacro -%}