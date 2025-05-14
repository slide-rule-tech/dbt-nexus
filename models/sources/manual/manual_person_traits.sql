{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'persons', 'realtime']) }}

with unpivoted_traits AS (
    {{ unpivot_traits(
        model_name='manual_persons_base',
        identifier_columns=['email', 'phone', 'user_id']
    ) }}
)

SELECT
   *
FROM unpivoted_traits
where trait_value is not null
and trait_value != 'null'
order by event_id desc