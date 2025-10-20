{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

{{ nexus.join_and_rename_or_drop(
    rename='drop',
    ref1=ref('base_segment_all_tracks'),
    ref2=ref('base_segment_selected_tracks'),
    id1='id',
    id2='id',
    prefix2=''
) }}