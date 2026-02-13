-- Measurement Unit Consistency Test
-- Warns if the same measurement_name has multiple different value_unit values
-- across sources. Catches both true unit mismatches (USD vs EUR) and casing
-- inconsistencies (USD vs usd) since both indicate sources that need alignment.
--
-- Severity: warn (does not block builds, but surfaces data quality issues)

{{ config(severity='warn') }}

with distinct_pairs as (
    select distinct
        measurement_name,
        value_unit
    from {{ ref('nexus_event_measurements_unioned') }}
    where measurement_name is not null
      and value_unit is not null
),

measurement_units as (
    select
        measurement_name,
        count(*) as distinct_units
    from distinct_pairs
    group by measurement_name
)

select
    mu.measurement_name,
    mu.distinct_units
from measurement_units mu
where mu.distinct_units > 1
