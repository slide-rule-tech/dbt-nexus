# Edge Quality Validation

Edge quality validation helps identify and prevent problematic identifier
connections that can cause over-merging and performance issues in identity
resolution.

## Overview

In identity resolution, edges represent connections between identifiers (e.g.,
an email and a phone number that appear together in an event). When an
identifier has too many connections to different values, it can cause massive
over-merging where unrelated entities get incorrectly linked together.

Edge quality validation provides:

- **Analysis**: Identify problematic identifiers even when filters are enabled
- **Autofilters**: Automatically exclude problematic edges from identity
  resolution
- **Tests**: Prevent builds from proceeding if filtered edges still exceed
  thresholds

## Configuration

Edge quality validation is configured in `dbt_project.yml` under the
`nexus.edge_quality` section:

```yaml
vars:
  nexus:
    edge_quality:
      critical_threshold: 50 # Maximum connections for CRITICAL severity
      critical_autofilter: false # Auto-filter identifiers exceeding critical_threshold
      error_threshold: 20 # Maximum connections for ERROR severity
      error_autofilter: false # Auto-filter identifiers exceeding error_threshold
      warning_threshold: 10 # Maximum connections for WARNING severity
```

### Configuration Options

- **`critical_threshold`** (default: 50): Connection count threshold for
  CRITICAL severity. Identifiers with more connections are flagged as critical.
- **`critical_autofilter`** (default: false): When `true`, automatically filters
  out all edges involving identifiers that exceed `critical_threshold` from
  `nexus_entity_identifiers_edges`.
- **`error_threshold`** (default: 20): Connection count threshold for ERROR
  severity. Used by tests to fail builds.
- **`error_autofilter`** (default: false): When `true`, automatically filters
  out all edges involving identifiers that exceed `error_threshold` from
  `nexus_entity_identifiers_edges`.
- **`warning_threshold`** (default: 10): Connection count threshold for WARNING
  severity. Used for informational analysis only.

### How Autofilters Work

When `critical_autofilter` or `error_autofilter` is enabled, the
`create_identifier_edges` macro filters edges **before** they're stored in
`nexus_entity_identifiers_edges`. This means:

1. The filter calculates total connections across **all sources** for each
   identifier
2. If an identifier exceeds the threshold, **all edges** involving that
   identifier are removed
3. This happens at build time, so downstream models only see filtered edges
4. The `edge_distributions` analysis model shows **unfiltered** data for
   investigation

**Example**: If `error_autofilter: true` and an email has 25 total connections
(20 from kafka, 5 from timx), all edges involving that email are filtered out
because 25 > 20 (error_threshold).

## Analysis Model: `edge_distributions`

The `edge_distributions` model provides analysis of **all** edges (unfiltered),
allowing you to investigate issues even when autofilters are enabled.

### Querying the Analysis

```sql
-- View all problematic identifiers by severity
select
    severity,
    count(*) as identifier_count,
    max(unique_connections) as max_connections,
    avg(unique_connections) as avg_connections
from {{ ref('edge_distributions') }}
group by severity
order by severity desc;

-- Find specific problematic identifiers
select
    identifier_type_a,
    identifier_value_a,
    unique_connections,
    connected_types,
    source_distribution,
    severity
from {{ ref('edge_distributions') }}
where severity in ('CRITICAL', 'ERROR')
order by unique_connections desc;

-- Investigate which sources are causing issues
select
    severity,
    source_distribution,
    count(*) as identifier_count,
    avg(unique_connections) as avg_connections
from {{ ref('edge_distributions') }}
where severity != 'OK'
group by severity, source_distribution
order by severity desc, avg_connections desc;
```

### Model Columns

- **`entity_type_a`**: Entity type (e.g., 'person')
- **`identifier_type_a`**: Identifier type (e.g., 'email', 'phone')
- **`identifier_value_a`**: The actual identifier value
- **`unique_connections`**: Count of distinct identifiers this connects to
- **`connected_types`**: Comma-separated list of identifier types this connects
  to
- **`source_distribution`**: Breakdown of connections by source (e.g., "kafka
  (20), timx (10)")
- **`severity`**: One of 'CRITICAL', 'ERROR', 'WARNING', or 'OK'

### Understanding Severity Levels

- **CRITICAL** (> `critical_threshold`): Extremely problematic identifiers that
  can cause massive over-merging
- **ERROR** (> `error_threshold`): Problematic identifiers that will cause test
  failures
- **WARNING** (> `warning_threshold`): Identifiers worth investigating but may
  be acceptable
- **OK** (≤ `warning_threshold`): Normal identifiers with acceptable connection
  counts

## Tests

The `test_edge_quality_thresholds` test validates that the **filtered**
`nexus_entity_identifiers_edges` table doesn't contain identifiers exceeding the
error threshold.

### Test Behavior

- **Reads from filtered edges**: The test queries
  `nexus_entity_identifiers_edges` (after autofilters are applied), not
  `edge_distributions`
- **Fails on error threshold**: If any identifier in filtered edges exceeds
  `error_threshold`, the build fails
- **Doesn't block with autofilters**: When `error_autofilter: true`, the test
  should pass because problematic edges are already filtered out

### Running Tests

```bash
# Run all tests
dbt test

# Run only edge quality tests
dbt test --select test_edge_quality_thresholds

# Run with specific selector
dbt test --select test_type:data
```

### Test Output

When the test fails, it returns identifiers in filtered edges that still exceed
the error threshold:

```text
Failure in test test_edge_quality_thresholds
  Got 3 results, configured to fail if != 0

  Example results:
  - entity_type: person, identifier_type: email, identifier_value: example@email.com, unique_connections: 23
```

## Best Practices

### 1. Start with Analysis First

Before enabling autofilters, analyze `edge_distributions` to understand your
data:

```sql
-- Get overview of issues
select severity, count(*)
from {{ ref('edge_distributions') }}
group by severity;
```

### 2. Enable Autofilters Gradually

1. Start with `critical_autofilter: true` only
2. Monitor `edge_distributions` to see what's being filtered
3. Investigate filtered identifiers to determine if they're legitimate issues
4. Once stable, consider enabling `error_autofilter: true`

### 3. Address Root Causes

Autofilters are a safety measure, but you should address root causes:

- **Problematic source data**: Filter bad identifiers at the source (e.g.,
  placeholder emails, invalid GA4 client IDs)
- **Data quality issues**: Investigate why legitimate identifiers have too many
  connections
- **Business logic problems**: Review whether identifiers should truly be
  connecting

### 4. Monitor Regularly

Query `edge_distributions` regularly to catch new issues:

```sql
-- Weekly monitoring query
select
    date_trunc('week', current_date()) as week,
    severity,
    count(*) as identifier_count
from {{ ref('edge_distributions') }}
group by severity
having severity != 'OK';
```

### 5. Use Source Attribution

The `source_distribution` column helps identify which data sources are causing
problems:

```sql
-- Find sources causing most issues
select
    source_distribution,
    severity,
    count(*) as count
from {{ ref('edge_distributions') }}
where severity in ('CRITICAL', 'ERROR')
group by source_distribution, severity
order by count desc;
```

## Troubleshooting

### Test Fails Even with Autofilters Enabled

If `test_edge_quality_thresholds` fails when `error_autofilter: true`, it means:

1. Some identifiers still exceed the threshold after filtering
2. This could indicate a bug in the filter logic
3. Check that total connections are being calculated correctly (across all
   sources)

### High CRITICAL Count in Analysis

If `edge_distributions` shows many CRITICAL identifiers:

1. This is expected if autofilters are disabled
2. Review if these are legitimate issues or data quality problems
3. Consider filtering problematic identifiers at source level (see source model
   filters)

### Filtered Edges Still Have Issues

If filtered edges (`nexus_entity_identifiers_edges`) still contain problematic
identifiers:

1. Verify autofilter configuration is correct in `dbt_project.yml`
2. Rebuild `nexus_entity_identifiers_edges` to apply filters
3. Check that thresholds are set appropriately for your data

## Related Models

- **`nexus_entity_identifiers_edges`**: The filtered edge table used in identity
  resolution
- **`nexus_entity_identifiers`**: The raw identifier table before edge creation
- **`test_edge_quality_thresholds`**: Test that validates filtered edge quality

## See Also

- Source-level filtering examples:
  - Kafka GA4 client ID filtering:
    `models/sources/kafka/intermediate/dtc_enrollment_api_enrollment_person_identifiers.sql`
  - TIMX placeholder email filtering:
    `models/sources/timx/intermediate/timx_party_created_person_identifiers.sql`
