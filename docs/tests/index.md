---
title: Testing Reference
tags: [reference, testing, data-quality, validation]
summary:
  Complete reference for all data quality tests in the nexus package, including
  uniqueness, not-null, and composite key validations.
---

# Testing Reference

The nexus package includes comprehensive data quality tests to ensure ID
uniqueness, data integrity, and proper relationships between models. All tests
are defined in `models/nexus-models/nexus.yml`.

---

## 1. Test Categories

### Primary Key Tests

- **Uniqueness**: Ensures no duplicate IDs across all records
- **Not Null**: Ensures all ID fields have values

### Composite Key Tests

- **Multi-column uniqueness**: Validates unique combinations across multiple
  fields
- **Edge relationship integrity**: Ensures proper identifier connections

### Data Integrity Tests

- **Foreign key relationships**: Validates references between models
- **Business rule compliance**: Ensures data follows expected patterns

---

## 2. Event-Level Tests

### nexus_events

**Purpose**: Validates the unified events table from all enabled sources.

```yaml
tests:
  - unique:
      column_name: event_id
      config:
        severity: error

columns:
  - name: event_id
    tests:
      - not_null:
          config:
            severity: error
  - name: occurred_at
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each event has a unique `event_id`
- No events are missing IDs or timestamps
- Events from all sources (Gmail, Google Calendar, Notion) are properly unified

**Common failures**: Duplicate event IDs when source models generate non-unique
IDs.

---

## 3. Identifier-Level Tests

### nexus_person_identifiers

**Purpose**: Validates person identifiers from all sources have unique IDs.

```yaml
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
```

**What it tests**:

- Each person identifier record has a unique ID
- No person identifiers are missing IDs
- Person identifiers from Gmail, Google Calendar, and Notion are properly
  deduplicated

**Common failures**:

- Same person appears multiple times with different roles but same ID
- Duplicate source data not properly deduplicated
- Missing role or timestamp in ID generation

### nexus_group_identifiers

**Purpose**: Validates group identifiers (domains, organizations) have unique
IDs.

```yaml
tests:
  - unique:
      column_name: group_identifier_id
      config:
        severity: error

columns:
  - name: group_identifier_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each group identifier record has a unique ID
- No group identifiers are missing IDs
- Group identifiers properly deduplicated when multiple people from same domain
  attend same event

**Common failures**:

- Multiple employees from same company create duplicate group records
- Missing deduplication in source models
- Role not included in ID generation

### nexus_membership_identifiers

**Purpose**: Validates person-to-group membership relationships have unique IDs.

```yaml
tests:
  - unique:
      column_name: membership_identifier_id
      config:
        severity: error

columns:
  - name: membership_identifier_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each membership relationship has a unique ID
- No memberships are missing IDs
- Same person can belong to multiple groups with different roles

**Common failures**:

- Same person-group combination with different roles gets same ID
- Missing role in membership ID generation

---

## 4. Trait-Level Tests

### nexus_person_traits

**Purpose**: Validates person traits (names, emails, etc.) have unique IDs.

```yaml
tests:
  - unique:
      column_name: person_trait_id
      config:
        severity: error

columns:
  - name: person_trait_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each person trait record has a unique ID
- No person traits are missing IDs
- Person traits properly linked to identifiers

### nexus_group_traits

**Purpose**: Validates group traits (domain names, organization details) have
unique IDs.

```yaml
tests:
  - unique:
      column_name: group_trait_id
      config:
        severity: error

columns:
  - name: group_trait_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each group trait record has a unique ID
- No group traits are missing IDs
- Group traits properly linked to identifiers

---

## 5. Resolved Entity Tests

### nexus_persons

**Purpose**: Validates final resolved person entities after identity resolution.

```yaml
tests:
  - unique:
      column_name: person_id
      config:
        severity: error

columns:
  - name: person_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each resolved person has a unique final ID
- Identity resolution properly merged duplicate identifiers
- No persons are missing final IDs

### nexus_groups

**Purpose**: Validates final resolved group entities after identity resolution.

```yaml
tests:
  - unique:
      column_name: group_id
      config:
        severity: error

columns:
  - name: group_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each resolved group has a unique final ID
- Identity resolution properly merged duplicate identifiers
- No groups are missing final IDs

### nexus_memberships

**Purpose**: Validates final resolved membership relationships.

```yaml
tests:
  - unique:
      column_name: membership_id
      config:
        severity: error

columns:
  - name: membership_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each resolved membership has a unique final ID
- Memberships properly link resolved persons to resolved groups
- No memberships are missing final IDs

---

## 6. Participant-Level Tests

### nexus_person_participants

**Purpose**: Validates person participation in events with proper role handling.

```yaml
tests:
  - unique:
      column_name: person_participant_id
      config:
        severity: error

columns:
  - name: person_participant_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each person-event-role combination has unique participant ID
- Same person can participate in same event with multiple roles
- No participants are missing IDs

**Common failures**:

- Role not included in participant ID generation
- Same person-event combination with different roles gets same ID

### nexus_group_participants

**Purpose**: Validates group participation in events with proper role handling.

```yaml
tests:
  - unique:
      column_name: group_participant_id
      config:
        severity: error

columns:
  - name: group_participant_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each group-event-role combination has unique participant ID
- Same group can participate in same event with multiple roles
- No participants are missing IDs

**Common failures**:

- Role not included in participant ID generation
- Same group-event combination with different roles gets same ID

---

## 7. Identity Resolution Tests

### nexus_resolved_person_identifiers

**Purpose**: Validates resolved person identifiers after identity resolution
processing.

```yaml
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
```

**What it tests**:

- Resolved identifiers maintain unique IDs
- Identity resolution process doesn't create duplicates
- All identifiers properly linked to resolved persons

### nexus_resolved_group_identifiers

**Purpose**: Validates resolved group identifiers after identity resolution
processing.

```yaml
tests:
  - unique:
      column_name: group_identifier_id
      config:
        severity: error

columns:
  - name: group_identifier_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Resolved identifiers maintain unique IDs
- Identity resolution process doesn't create duplicates
- All identifiers properly linked to resolved groups

### nexus_resolved_person_traits

**Purpose**: Validates resolved person traits after identity resolution
processing.

```yaml
tests:
  - unique:
      column_name: person_trait_id
      config:
        severity: error

columns:
  - name: person_trait_id
    tests:
      - not_null:
          config:
            severity: error
```

### nexus_resolved_group_traits

**Purpose**: Validates resolved group traits after identity resolution
processing.

```yaml
tests:
  - unique:
      column_name: group_trait_id
      config:
        severity: error

columns:
  - name: group_trait_id
    tests:
      - not_null:
          config:
            severity: error
```

---

## 8. Edge Relationship Tests

### nexus_person_identifiers_edges

**Purpose**: Validates edges connecting person identifiers for identity
resolution.

```yaml
tests:
  - unique:
      column_name:
        "edge_id || '|' || identifier_type_a || '|' || identifier_value_a || '|'
        || identifier_type_b || '|' || identifier_value_b"
      config:
        severity: error

columns:
  - name: edge_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each edge relationship is unique across all identifier combinations
- No edges are missing IDs
- Bidirectional edges are properly handled

**Note**: Uses concatenated string syntax for composite key uniqueness testing.

### nexus_group_identifiers_edges

**Purpose**: Validates edges connecting group identifiers for identity
resolution.

```yaml
tests:
  - unique:
      column_name:
        "edge_id || '|' || identifier_type_a || '|' || identifier_value_a || '|'
        || identifier_type_b || '|' || identifier_value_b"
      config:
        severity: error

columns:
  - name: edge_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each edge relationship is unique across all identifier combinations
- No edges are missing IDs
- Bidirectional edges are properly handled

---

## 9. State Management Tests

### nexus_states

**Purpose**: Validates entity state tracking and transitions.

```yaml
tests:
  - unique:
      column_name: state_id
      config:
        severity: error

columns:
  - name: state_id
    tests:
      - not_null:
          config:
            severity: error
```

**What it tests**:

- Each state record has a unique ID
- State transitions are properly tracked
- No states are missing IDs

---

## 10. Running Tests

### Run All Tests

```bash
dbt test --models nexus_*
```

### Run Specific Model Tests

```bash
dbt test --models nexus_person_identifiers
dbt test --models nexus_group_participants
```

### Run Only Uniqueness Tests

```bash
dbt test --models nexus_* --select test_type:unique
```

### Run Tests with Increased Verbosity

```bash
dbt test --models nexus_* --debug
```

---

## 11. Test Failure Investigation

When tests fail, use these approaches:

### 1. Check Test Results

```bash
# View compiled test SQL
cat target/compiled/nexus/models/nexus-models/nexus.yml/unique_nexus_person_identifiers_person_identifier_id.sql
```

### 2. Run Diagnostic Queries

See [Troubleshooting Duplicates](../how-to/troubleshooting-duplicates.md) for
specific diagnostic queries.

### 3. Validate Fixes

```bash
# Rebuild and test incrementally
dbt run --models source_model
dbt run --models nexus_model
dbt test --models nexus_model
```

---

## 12. Test Configuration

### Severity Levels

- **error**: Test failure stops execution (default for all nexus tests)
- **warn**: Test failure logs warning but continues

### Custom Test Thresholds

```yaml
tests:
  - unique:
      column_name: person_id
      config:
        severity: error
        error_if: ">= 1" # Fail if any duplicates
        warn_if: ">= 0" # Warn if any issues
```

### Test Tags

All nexus tests are automatically tagged for easy filtering:

```bash
dbt test --models tag:nexus
dbt test --models tag:identity-resolution
```

For troubleshooting specific test failures, see the
[Troubleshooting Duplicates Guide](../how-to/troubleshooting-duplicates.md).
