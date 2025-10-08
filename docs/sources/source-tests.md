---
title: Source Testing Best Practices
tags: [testing, sources, data-quality, best-practices]
summary:
  Essential guide for creating comprehensive tests for source models to ensure
  data quality before nexus processing.
---

# Source Testing Best Practices

**Strongly Recommended**: Test the union layer of your source models before they
enter the nexus pipeline. One good test at the union layer is better than
multiple overlapping tests across layers.

## Testing Philosophy: Union Layer Only

**Default approach**: Test only the union layer models (e.g., `kafka_events`,
`kafka_person_identifiers`, `kafka_person_traits`).

### Why Test Only the Union Layer?

1. **Avoid Redundancy**: Testing base, normalized, and intermediate layers
   creates overlapping tests that catch the same issues multiple times
2. **Focus on Output**: The union layer is what feeds into nexus - if it's
   correct, the pipeline works
3. **Faster Execution**: Fewer tests mean faster CI/CD runs
4. **Easier Maintenance**: One set of tests to maintain instead of four
5. **Clear Ownership**: Issues surface at the final integration point, not
   buried in intermediate layers

### When to Test Lower Layers

Only add tests to base/normalized/intermediate layers when:

- **Debugging specific issues** that require layer-by-layer validation
- **Complex transformations** where intermediate validation adds value
- **Business-critical fields** that must be validated early in the pipeline
- **Normalized tests** where the nromalized tables require lots of cleaning and
  are used later.

## Why Source Tests Matter

Union layer tests are your **quality gate** before nexus processing:

- **Early Detection**: Catch problems before they propagate through nexus
  identity resolution
- **Data Quality Assurance**: Ensure IDs are unique and required fields are
  populated
- **Pipeline Reliability**: Prevent downstream failures in identity resolution
- **Business Logic Validation**: Verify data follows expected patterns and
  constraints

---

## Essential Union Layer Test Categories

### 1. **Uniqueness Tests**

Test that primary identifiers are unique at the union layer:

```yaml
tests:
  - unique:
      column_name: event_id
      config:
        severity: error
```

### 2. **Not Null Tests**

Ensure critical fields are always populated in final output:

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

**Important**: Use the correct ID prefixes from the nexus `create_nexus_id`
macro:

- Events: `'evt_%'`
- Person Identifiers: `'per_idfr_%'`
- Person Traits: `'per_tr_%'` (note: not `'per_trt_%'`)
- Group Identifiers: `'grp_idfr_%'`
- Group Traits: `'grp_tr_%'`

### 4. **Business Logic Tests** (Use Sparingly)

Only test source-specific business rules that aren't already caught by other
tests:

```yaml
- accepted_values:
    values: ["enrollment", "renewal"]
    config:
      severity: warn
```

---

## Complete Example: Kafka Source Tests

Here's a streamlined test suite focusing on the union layer:

```yaml
version: 2

models:
  # Union Layer Tests - Events
  - name: kafka_events
    description:
      "Union layer - All Kafka source events combined into nexus-compatible
      format"
    tests:
      - unique:
          column_name: event_id
          config:
            severity: error
    columns:
      - name: event_id
        description: "Unique nexus event identifier"
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
        description: "Type of event"
        tests:
          - not_null:
              config:
                severity: error

  # Union Layer Tests - Person Identifiers
  - name: kafka_person_identifiers
    description:
      "Union layer - All person identifiers from Kafka sources combined"
    tests:
      - unique:
          column_name: person_identifier_id
          config:
            severity: error
    columns:
      - name: person_identifier_id
        description: "Unique nexus person identifier ID"
        tests:
          - not_null:
              config:
                severity: error
          - dbt_utils.expression_is_true:
              expression: "like 'per_idfr_%'"
              config:
                severity: warn
      - name: identifier_type
        description: "Type of person identifier"
        tests:
          - not_null:
              config:
                severity: error
      - name: identifier_value
        description: "Value of the person identifier"
        tests:
          - not_null:
              config:
                severity: error

  # Union Layer Tests - Person Traits
  - name: kafka_person_traits
    description: "Union layer - All person traits from Kafka sources combined"
    tests:
      - unique:
          column_name: person_trait_id
          config:
            severity: error
    columns:
      - name: person_trait_id
        description: "Unique nexus person trait ID"
        tests:
          - not_null:
              config:
                severity: error
          - dbt_utils.expression_is_true:
              expression: "like 'per_tr_%'"
              config:
                severity: warn
      - name: trait_name
        description: "Name of the person trait"
        tests:
          - not_null:
              config:
                severity: error
      - name: trait_value
        description: "Value of the person trait"
        tests:
          - not_null:
              config:
                severity: error
```

---

## Running Source Tests

### Test Union Layer Models

```bash
# Test all union layer models in a source
dbt test --select kafka_events kafka_person_identifiers kafka_person_traits

# Test just events
dbt test --select kafka_events

# Build and test everything in the source folder
dbt build --select models/sources/kafka/

# Test with increased verbosity for debugging
dbt test --select kafka_events --debug
```

### Test by Tag

```bash
# Test all identity resolution models across all sources
dbt test --select tag:identity-resolution

# Test only events models
dbt test --select tag:events
```

---

## Test Configuration Guidelines

### One Good Test is Better Than Multiple Overlapping Tests

**Principle**: Avoid testing the same thing multiple times across different
layers.

**Example of redundancy to avoid**:

```yaml
# ❌ Bad: Testing uniqueness at every layer
base_model:
  tests:
    - unique: enrollment_id
normalized_model:
  tests:
    - unique: enrollment_id
intermediate_model:
  tests:
    - unique: event_id
union_model:
  tests:
    - unique: event_id
```

**Better approach**:

```yaml
# ✅ Good: Test once at the union layer
union_model:
  tests:
    - unique: event_id
```

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
- Not null tests on required nexus fields (event_id, occurred_at, etc.)
- Critical business logic that would break nexus processing

**Use `warn` severity for**:

- ID pattern validation (nexus prefixes like 'evt\_%')
- Optional business logic validation
- Data quality checks that shouldn't stop builds

---

## Union Layer Test Patterns

### Events Union Model

Essential tests for `{source}_events` models:

```yaml
- name: source_events
  tests:
    - unique:
        column_name: event_id
  columns:
    - name: event_id
      tests:
        - not_null
        - dbt_utils.expression_is_true:
            expression: "like 'evt_%'"
            config:
              severity: warn
    - name: occurred_at
      tests:
        - not_null
    - name: event_type
      tests:
        - not_null
```

### Person Identifiers Union Model

Essential tests for `{source}_person_identifiers` models:

```yaml
- name: source_person_identifiers
  tests:
    - unique:
        column_name: person_identifier_id
  columns:
    - name: person_identifier_id
      tests:
        - not_null
        - dbt_utils.expression_is_true:
            expression: "like 'per_idfr_%'"
            config:
              severity: warn
    - name: identifier_type
      tests:
        - not_null
    - name: identifier_value
      tests:
        - not_null
```

### Person Traits Union Model

Essential tests for `{source}_person_traits` models:

```yaml
- name: source_person_traits
  tests:
    - unique:
        column_name: person_trait_id
  columns:
    - name: person_trait_id
      tests:
        - not_null
        - dbt_utils.expression_is_true:
            expression: "like 'per_tr_%'"
            config:
              severity: warn
    - name: trait_name
      tests:
        - not_null
    - name: trait_value
      tests:
        - not_null
```

---

## Common Test Failures and Solutions

### Duplicate IDs at Union Layer

**Problem**: `unique` test fails on primary key in union model

**Root causes**:

- Duplicate IDs in intermediate models being unioned
- Same record appearing in multiple intermediate models
- ID generation not including enough uniqueness factors

**Solutions**:

1. Check each intermediate model for duplicates:
   ```bash
   dbt test --select source_intermediate_model_1 source_intermediate_model_2
   ```
2. Verify ID generation includes all necessary uniqueness factors
3. Add deduplication logic in normalized layer if needed

### Missing Required Fields (NULL values)

**Problem**: `not_null` test fails at union layer

**Root causes**:

- Source data has NULL timestamps or required fields
- Transformation logic creating NULLs
- Type casting failures

**Solutions**:

1. Add filter in normalized layer: `where occurred_at is not null`
2. Check intermediate models for transformation issues
3. Coordinate with data team on upstream data quality

### ID Pattern Violations

**Problem**: `expression_is_true` test fails for ID patterns (e.g., expecting
`'per_tr_%'` but finding `'per_trt_%'`)

**Common mistake**: Wrong ID prefix pattern in test

**Solutions**:

1. Check the `create_nexus_id` macro for correct prefixes:
   - Events: `'evt_%'`
   - Person Identifiers: `'per_idfr_%'`
   - Person Traits: `'per_tr_%'` (NOT `'per_trt_%'`)
2. Update test pattern to match macro output
3. Ensure using `create_nexus_id` macro (not manual ID generation)

---

## Integration with Nexus Pipeline

Union layer tests act as your quality gate before nexus processing:

1. **Union Layer Tests** → Validate final source output (events, identifiers,
   traits)
2. **Nexus Processing** → Identity resolution and entity management
3. **Nexus Tests** → Validate resolved entities and relationships

This focused approach catches integration issues at the critical junction point
without redundant testing at every transformation layer.

---

## Summary: Testing Best Practices

**Key Principles**:

1. ✅ **Test the union layer** - This is where sources feed into nexus
2. ✅ **One good test** - Avoid redundant tests across multiple layers
3. ✅ **Focus on critical fields** - ID uniqueness, NULL checks, required fields
4. ✅ **Use appropriate severity** - `error` for critical, `warn` for patterns
5. ✅ **Know your ID prefixes** - `'evt_%'`, `'per_idfr_%'`, `'per_tr_%'`

**Default Test Suite** for each union model:

- **Uniqueness** of primary ID
- **Not null** on critical fields
- **ID pattern** validation (warn severity)
- **Minimal business logic** tests (only when necessary)

---

## Next Steps

After implementing union layer tests:

1. **Run tests in CI/CD** - Fast, focused test execution
2. **Monitor failures** - Issues surface at the integration point
3. **Keep tests simple** - Resist the urge to add redundant tests
4. **Update patterns** - As you add new event types or identifiers

For nexus-specific testing, see the [Testing Reference](index.md) for
comprehensive coverage of all nexus model tests.
