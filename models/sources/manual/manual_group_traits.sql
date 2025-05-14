{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

with unpivoted_traits AS (
    {{ unpivot_traits(
        model_name='manual_groups_base',
        identifier_columns=['domain']
    ) }}
)

SELECT
   *
FROM unpivoted_traits
where trait_value is not null
order by event_id desc 