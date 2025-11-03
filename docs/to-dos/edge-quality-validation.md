---
title: Edge Quality Validation at Creation Time
tags: [todo, identity-resolution, data-quality, performance]
summary:
  Add pre-resolution edge quality checks to flag problematic identifier
  connections before they cause massive over-merging and performance issues.
---

# Edge Quality Validation at Creation Time

## Problem Statement

Identity resolution performance and correctness are heavily impacted by
poor-quality edges. A single bad identifier that's connected to many other
identifiers can cascade through transitive closure, causing:

- **Massive over-merging**: Hundreds or thousands of identifiers incorrectly
  resolved to the same person
- **Performance degradation**: Exponential blow-up in recursive CTE execution
- **Late detection**: Issues only discovered after expensive resolution runs

**Example**: A single GHL contact ID appeared in 105 different Segment events
with 103 different email addresses. Through transitive closure, this caused 738
identifiers to incorrectly merge into one person.

## Current State

Quality issues are only detected **after** identity resolution completes,
through:

- Post-resolution diagnostic queries
- Manual investigation of suspicious persons
- Performance monitoring (slow runs)

This is too late—the expensive recursive CTE has already run and produced
incorrect results.

## Proposed Solution

Add edge quality checks **at edge creation time** in
`nexus_entity_identifiers_edges.sql` to flag problematic edges before they enter
the resolution process.

### Distribution Analysis

Create a histogram showing how many unique identifier_values each identifier is
connected to:

```sql
-- Flag identifiers with suspiciously high connection counts
with edge_distribution as (
    select
        entity_type_a,
        identifier_type_a,
        identifier_value_a,
        count(distinct identifier_value_b) as unique_connections
    from {{ ref('nexus_entity_identifiers_edges') }}
    group by entity_type_a, identifier_type_a, identifier_value_a
)

select * from edge_distribution
where unique_connections > {{ var('nexus_max_connections_threshold', 10) }}
order by unique_connections desc
```

### Thresholds

Most legitimate identifiers connect to 2-3 others (e.g., email ↔ phone ↔
patient_id). Connections >10 are suspicious:

- **Normal**: 1-5 connections
- **Warning**: 6-10 connections
- **Error**: >10 connections (block edge creation or flag for review)

### Implementation Options

#### Option 1: Blocking Check (Recommended for First Pass)

Create a dbt test that fails if any identifier exceeds thresholds:

```sql
-- tests/test_edge_quality_thresholds.sql
select
    entity_type_a,
    identifier_type_a,
    identifier_value_a,
    unique_connections
from {{ ref('nexus_entity_identifiers_edges_distribution') }}
where unique_connections > 10
```

Config in `dbt_project.yml`:

```yaml
tests:
  gameday:
    test_edge_quality_thresholds:
      +severity: error
```

#### Option 2: Non-Blocking Diagnostic Model

Create an analysis model that flags problematic edges for review:

```sql
-- models/analysis/edge_quality_check.sql
{{ config(materialized='table', tags=['analysis']) }}

with edge_distribution as (
    select
        entity_type_a,
        identifier_type_a,
        identifier_value_a,
        count(distinct identifier_value_b) as unique_connections,
        listagg(distinct identifier_type_b, ', ') as connected_types
    from {{ ref('nexus_entity_identifiers_edges') }}
    group by entity_type_a, identifier_type_a, identifier_value_a
)

select
    entity_type_a,
    identifier_type_a,
    identifier_value_a,
    unique_connections,
    connected_types,
    case
        when unique_connections > 50 then 'CRITICAL'
        when unique_connections > 20 then 'ERROR'
        when unique_connections > 10 then 'WARNING'
        else 'OK'
    end as severity
from edge_distribution
where unique_connections > 10
order by severity desc, unique_connections desc
```

#### Option 3: Statistical Analysis

Use z-scores to detect outliers within each identifier type:

```sql
with edge_distribution as (
    select
        entity_type_a,
        identifier_type_a,
        identifier_value_a,
        count(distinct identifier_value_b) as unique_connections
    from {{ ref('nexus_entity_identifiers_edges') }}
    group by entity_type_a, identifier_type_a, identifier_value_a
),

type_statistics as (
    select
        entity_type_a,
        identifier_type_a,
        avg(unique_connections) as avg_connections,
        stddev(unique_connections) as stddev_connections
    from edge_distribution
    group by entity_type_a, identifier_type_a
),

flagged_edges as (
    select
        ed.*,
        ts.avg_connections,
        ts.stddev_connections,
        (ed.unique_connections - ts.avg_connections) / nullif(ts.stddev_connections, 0) as z_score
    from edge_distribution ed
    join type_statistics ts
        on ed.entity_type_a = ts.entity_type_a
        and ed.identifier_type_a = ts.identifier_type_a
)

select * from flagged_edges
where z_score > 3  -- Statistical outlier
order by z_score desc
```

## Expected Impact

### Data Quality

- **Early detection**: Catch problematic edges before they cascade through
  resolution
- **Root cause identification**: Find sources with invalid identifier mappings
- **Validation**: Ensure edge creation logic is working correctly

### Performance

- **Faster resolution**: Fewer bad edges mean smaller graphs and faster
  recursion
- **Controlled recursion depth**: Prevent exponential expansion from problematic
  connections
- **Resource efficiency**: Identify issues before consuming large compute
  resources

### Operational

- **Automated checks**: Integrate into CI/CD to catch issues early
- **Actionable alerts**: Flag specific identifiers that need investigation
- **Historical tracking**: Monitor edge quality trends over time

## Success Criteria

- [ ] Detect identifiers with >10 connections before resolution runs
- [ ] Identify Segment GHL_ID issue through automated check
- [ ] Block or warn on edge creation exceeding thresholds
- [ ] Reduce over-merged person resolution by 95%+
- [ ] Provide clear root cause for flagged edges

## Implementation Plan

### Phase 1: Analysis Model (Week 1)

Create `models/analysis/edge_quality_check.sql` to manually inspect edge
distribution patterns.

### Phase 2: Automated Tests (Week 2)

Add dbt tests that fail if threshold violations are detected during edge
creation.

### Phase 3: Source Attribution (Week 3)

Enhance check to identify which source contributed the problematic edges.

### Phase 4: Filtering (Future)

Consider adding optional edge filtering logic to exclude suspicious connections
automatically.

## Related Documentation

- [Edge Validation Testing Strategy](edge-validation-testing.md) -
  Post-resolution validation
- [Reduce Recursive CTE Performance](reduce-recursive-cte.md) - Performance
  optimization
- [Identity Resolution Architecture](../identity-resolution/index.md) -
  Algorithm details
