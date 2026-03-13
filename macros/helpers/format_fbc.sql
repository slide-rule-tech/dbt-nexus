{%- macro format_fbc(fbclid_column='fbclid', occurred_at_column='fbclid_occurred_at') -%}
case
    when {{ fbclid_column }} is not null and {{ occurred_at_column }} is not null then
        'fb.1.' ||
        cast(extract(epoch from {{ occurred_at_column }}) * 1000 as bigint)::varchar ||
        '.' ||
        {{ fbclid_column }}
    else null
end
{%- endmacro -%}
