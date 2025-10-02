---
title: Source Testing Best Practices
tags: [testing, sources, data-quality, best-practices]
summary:
  Essential guide for creating comprehensive tests for source models to ensure
  data quality before nexus processing.
---

# Source Testing Best Practices

**Strongly Recommended**: Create comprehensive tests for all source models
before they enter the nexus pipeline. Source tests catch data quality issues
early and ensure reliable identity resolution.

## Why Source Tests Matter

Source tests are your **first line of defense** against data quality issues:

- **Early Detection**: Catch problems before they propagate through nexus
  processing
- **Data Quality Assurance**: Ensure IDs are unique and required fields are
  populated
- **Pipeline Reliability**: Prevent downstream failures in identity resolution
- **Business Logic Validation**: Verify data follows expected patterns and
  constraints

---

## Essential Source Test Categories

### 1. **Uniqueness Tests**

Test that primary identifiers are unique within each source:

```yaml
tests:
  - unique:
      column_name: event_id
      config:
        severity: error
```

### 2. **Not Null Tests**

Ensure critical fields are always populated:

```yaml
columns:
  - name: event_id
    tests:
      - not_null:
          config:
            severity: error
```

### 3. **ID Pattern Tests**

Validate that nexus IDs follow expected patterns:

```yaml
- dbt_utils.expression_is_true:
    expression: "like 'evt_%'"
    config:
      severity: warn
```

### 4. **Business Logic Tests**

Validate source-specific business rules:

```yaml
- accepted_values:
    values: ["web", "identity"]
    config:
      severity: warn
```

---

## Complete Example: Segment Source Tests

Here's the comprehensive test suite we created for Segment:

```yaml
version: 2

models:
  - name: segment_events
    description:
      "Unified Segment events table containing all event types (tracks, pages,
      identifies)"
    tests:
      - unique:
          column_name: event_id
          config:
            severity: error
    columns:
      - name: event_id
        description: "Unique identifier for the event"
        tests:
          - not_null:
              config:
                severity: error
          - dbt_utils.expression_is_true:
              expression: "like 'evt_%'"
              config:
                severity: warn
      - name: occurred_at
        description: "Timestamp when the event occurred"
        tests:
          - not_null:
              config:
                severity: error
      - name: event_type
        description: "Type of event (web, identity)"
        tests:
          - not_null:
              config:
                severity: error
          - accepted_values:
              values: ["web", "identity"]
              config:
                severity: warn
      - name: source
        description: "Source system (segment)"
        tests:
          - not_null:
              config:
                severity: error
          - accepted_values:
              values: ["segment"]
              config:
                severity: error

  - name: segment_person_identifiers
    description:
      "Unified Segment person identifiers table containing all person
      identifiers from tracks, pages, and identifies"
    tests:
      - unique:
          column_name: person_identifier_id
          config:
            severity: error
    columns:
      - name: person_identifier_id
        tests:
          - not_null:
              config:
                severity: error
          - dbt_utils.expression_is_true:
              expression: "like 'per_idfr_%'"
              config:
                severity: warn
      - name: identifier_type
        tests:
          - accepted_values:
              values: ["segment_anonymous_id", "user_id", "email"]
              config:
                severity: warn
```

---

## Running Source Tests

### Test All Models in a Source

```bash
# Test all Segment models and their dependencies
dbt test --select models/sources/segment/

# Test just the unioned models
dbt test --select segment_events segment_person_identifiers

# Build and test everything in the segment folder
dbt build --select models/sources/segment/
```

### Test Specific Model Types

```bash
# Test only events models
dbt test --select tag:events

# Test only person identifier models
dbt test --select tag:persons

# Test only identity resolution models
dbt test --select tag:identity-resolution
```

### Test Individual Models

```bash
# Test a specific model
dbt test --select segment_events

# Test with increased verbosity for debugging
dbt test --select segment_events --debug
```

---

## Test Configuration Guidelines

### Severity Levels

Use appropriate severity levels based on impact:

```yaml
# Critical data integrity - stop execution
config:
  severity: error

# Data quality warnings - log but continue
config:
  severity: warn
```

### Error vs Warning Guidelines

**Use `error` severity for**:

- Uniqueness constraints on primary keys
- Not null tests on required fields
- Source consistency (all records from expected source)

**Use `warn` severity for**:

- ID pattern validation (nexus prefixes)
- Business logic validation (accepted values)
- Data quality checks that shouldn't stop builds

---

## Source-Specific Test Patterns

### Event Sources

For sources that generate events:

```yaml
columns:
  - name: event_id
    tests:
      - unique
      - not_null
      - dbt_utils.expression_is_true:
          expression: "like 'evt_%'"
  - name: occurred_at
    tests:
      - not_null
  - name: source
    tests:
      - accepted_values:
          values: ["your_source_name"]
```

### Person Identifier Sources

For sources with person identifiers:

```yaml
columns:
  - name: person_identifier_id
    tests:
      - unique
      - not_null
      - dbt_utils.expression_is_true:
          expression: "like 'per_idfr_%'"
  - name: identifier_type
    tests:
      - accepted_values:
          values: ["email", "user_id", "phone", "custom_id"]
  - name: identifier_value
    tests:
      - not_null
```

---

## Common Test Failures and Solutions

### Duplicate IDs

**Problem**: `unique` test fails on primary key

**Solutions**:

- Check source data for actual duplicates
- Verify ID generation includes all necessary uniqueness factors
- Add role or timestamp to ID generation if needed

### Missing Required Fields

**Problem**: `not_null` test fails

**Solutions**:

- Filter out incomplete records in source model
- Add data quality checks in base layer
- Coordinate with data team on upstream data quality

### Pattern Violations

**Problem**: `expression_is_true` test fails for ID patterns

**Solutions**:

- Ensure using `create_nexus_id` macro correctly
- Check macro parameters (type, columns)
- Verify no manual ID generation bypassing macro

---

## Integration with Nexus Pipeline

Source tests ensure your models are ready for nexus processing:

1. **Source Tests** → Validate raw data quality
2. **Nexus Processing** → Identity resolution and entity management
3. **Nexus Tests** → Validate final pipeline output

This layered approach catches issues at the right level and ensures reliable
end-to-end data quality.

---

## Next Steps

After implementing source tests:

1. **Run tests regularly** as part of your CI/CD pipeline
2. **Monitor test results** and investigate failures promptly
3. **Expand test coverage** as you discover new data quality patterns
4. **Document test failures** and solutions for your team

For nexus-specific testing, see the [Testing Reference](index.md) for
comprehensive coverage of all nexus model tests.
