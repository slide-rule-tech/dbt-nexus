{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

select * from {{ nexus.nexus_source('segment', 'identifies') }}