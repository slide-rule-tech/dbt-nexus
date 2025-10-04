{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false)
) }}

select * from {{ nexus_source('segment', 'pages') }}
