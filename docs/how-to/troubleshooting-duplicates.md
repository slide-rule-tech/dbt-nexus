---
title: Troubleshooting Duplicate IDs
tags: [how-to, troubleshooting, testing, duplicates]
summary:
  Step-by-step guide to identify and fix duplicate ID issues in nexus models
  with sample queries and common solutions.
---

# Troubleshooting Duplicate IDs

This guide helps you identify and resolve duplicate ID issues in nexus models.
Duplicate IDs typically occur when the ID generation doesn't include enough
unique components or when there's duplicate data in source systems.

---

## 1. Identify Which Model Has Duplicates

When you see a uniqueness test failure, first identify which model and data
source is causing the issue:

```bash
# Run dbt test to see which models are failing
dbt test --models nexus_*
```

Look for error messages like:

```
Failure in test unique_nexus_person_identifiers_person_identifier_id
Got 2455 results, configured to fail if != 0
```

---

## 2. Find the Data Source Causing Duplicates

Use this query template to identify which data source has duplicates:

```sql
-- For person identifiers
SELECT source, COUNT(*) as duplicate_count
FROM (
    SELECT source, person_identifier_id, COUNT(*) as count
    FROM `your_project`.`your_dataset`.`nexus_person_identifiers`
    GROUP BY source, person_identifier_id
    HAVING COUNT(*) > 1
)
GROUP BY source
ORDER BY duplicate_count DESC;

-- For group identifiers
SELECT source, COUNT(*) as duplicate_count
FROM (
    SELECT source, group_identifier_id, COUNT(*) as count
    FROM `your_project`.`your_dataset`.`nexus_group_identifiers`
    GROUP BY source, group_identifier_id
    HAVING COUNT(*) > 1
)
GROUP BY source
ORDER BY duplicate_count DESC;

-- For membership identifiers
SELECT source, COUNT(*) as duplicate_count
FROM (
    SELECT source, membership_identifier_id, COUNT(*) as count
    FROM `your_project`.`your_dataset`.`nexus_membership_identifiers`
    GROUP BY source, membership_identifier_id
    HAVING COUNT(*) > 1
)
GROUP BY source
ORDER BY duplicate_count DESC;
```

---

## 3. Examine Specific Duplicate Records

Once you know the source, examine specific duplicates:

```sql
-- Find specific duplicate records
SELECT person_identifier_id, event_id, identifier_type, identifier_value, role, source, occurred_at
FROM `your_project`.`your_dataset`.`nexus_person_identifiers`
WHERE source = 'google_calendar'
AND person_identifier_id IN (
    SELECT person_identifier_id
    FROM `your_project`.`your_dataset`.`nexus_person_identifiers`
    WHERE source = 'google_calendar'
    GROUP BY person_identifier_id
    HAVING COUNT(*) > 1
)
ORDER BY person_identifier_id, occurred_at
LIMIT 10;
```

---

## 4. Common Duplicate Scenarios and Solutions

### Scenario 1: String "null" Values in Source Data

**Problem**: Source data contains string "null" values instead of actual NULL values,
causing duplicate person_identifier_ids when the same event has multiple identifier
types with "null" values.

**Example**:
```
event_id: evt_123
email: "null" (string)
phone: "null" (string)
-- Both generate same person_identifier_id because they hash to same value
```

**Solution**: Use `safe_cast_with_null_strings` macro to handle null string variations:

```sql
-- In unpivot macros, replace:
cast({{ col }} as string) as identifier_value

-- With:
{{ nexus.safe_cast_with_null_strings(col, api.Column.translate_type("string")) }} as identifier_value
```

**Helper Macro**:
```sql
{% macro safe_cast_with_null_strings(column_name, target_type) %}
  case 
    when {{ column_name }} is null then null
    when {{ column_name }} = 'null' then null
    when {{ column_name }} = 'NULL' then null
    when {{ column_name }} = 'None' then null
    when {{ column_name }} = 'none' then null
    when {{ column_name }} = '' then null
    else {{ dbt.safe_cast(column_name, api.Column.translate_type(target_type)) }}
  end
{% endmacro %}
```

### Scenario 2: Cross-Contamination Between Identifier Types

**Problem**: Same value used for different identifier types (e.g., phone number used as email),
creating duplicate person_identifier_ids.

**Example**:
```
person_identifier_id: per_idfr_abc123
identifier_type: email
identifier_value: "6307776986" (phone number)

person_identifier_id: per_idfr_abc123 (same ID!)
identifier_type: phone  
identifier_value: "6307776986" (same value)
```

**Solution**: Use validation macros to prevent cross-contamination:

```sql
-- Email validation
{{ nexus.validate_and_normalize_email(column.name) }}

-- Phone validation (filters out emails)
{{ nexus.validate_and_normalize_phone(column.name) }}
```

### Scenario 3: Missing Role in ID Generation

**Problem**: Same person/group appears multiple times with different roles but
same ID.

**Example**:

```
person_identifier_id: per_idfr_abc123
role: organizer
role: attendee
role: creator
```

**Solution**: Add role to ID generation in source models:

```sql
-- Before
{{ create_nexus_id('person_identifier', ['event_id', 'email', 'occurred_at']) }}

-- After
{{ create_nexus_id('person_identifier', ['event_id', 'email', 'role', 'occurred_at']) }}
```

### Scenario 2: Multiple People from Same Domain

**Problem**: Multiple employees from same company attend same event, creating
duplicate group identifiers.

**Solution**: Add deduplication to group identifier models:

```sql
-- Add GROUP BY to attendee domains CTE
attendee_domains AS (
    SELECT
        -- ... other fields ...
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
    GROUP BY base.nexus_event_id, attendee.domain, attendee.is_optional, base.start_time
)
```

### Scenario 3: Duplicate Source Data

**Problem**: Same person appears multiple times in source data for same event.

**Example**:

```sql
-- Check source data for duplicates
SELECT nexus_event_id, attendee.email, attendee.domain, attendee.is_optional
FROM `your_project`.`development`.`google_calendar_events_base` base,
UNNEST(base.attendees) as attendee
WHERE base.nexus_event_id = 'evt_12345'
AND attendee.email = 'john@company.com'
ORDER BY attendee.email;
```

**Solution**: Add deduplication to source models:

```sql
-- Add GROUP BY to remove source duplicates
GROUP BY base.nexus_event_id, attendee.email, attendee.is_optional, base.start_time
```

### Scenario 4: Missing Timestamp in ID Generation

**Problem**: Same identifier appears at different times but gets same ID.

**Solution**: Include timestamp in ID generation:

```sql
{{ create_nexus_id('person_identifier', ['event_id', 'email', 'role', 'occurred_at']) }}
```

### Scenario 5: Participant Role Duplicates

**Problem**: Same entity participates in event with multiple roles but gets same
participant ID.

**Solution**: Update `finalize_participants` macro to include role:

```sql
-- In finalize_participants macro
{{ create_nexus_id(entity_type ~ '_participant', ['event_id', entity_type ~ '_id', 'role']) }}
```

---

## 5. Testing Your Fixes

After implementing fixes:

1. **Rebuild source models first**:

```bash
dbt run --models gmail_person_identifiers google_calendar_person_identifiers
```

2. **Rebuild nexus models**:

```bash
dbt run --models nexus_person_identifiers
```

3. **Run tests**:

```bash
dbt test --models nexus_person_identifiers
```

4. **Verify duplicate count reduction**:

```sql
SELECT COUNT(*) as total_duplicates
FROM (
    SELECT person_identifier_id, COUNT(*) as count
    FROM `your_project`.`your_dataset`.`nexus_person_identifiers`
    GROUP BY person_identifier_id
    HAVING COUNT(*) > 1
);
```

---

## 6. Prevention Best Practices

### ID Generation Guidelines

1. **Always include role** when entities can have multiple roles
2. **Include timestamps** when the same identifier can appear at different times
3. **Use deduplication** in source models when raw data has duplicates
4. **Test incrementally** - fix one source at a time

### Source Model Patterns

```sql
-- Good: Includes role and deduplication
attendee_identifiers AS (
    SELECT
        {{ create_nexus_id('person_identifier', ['event_id', 'attendee.email', 'role', 'occurred_at']) }} as person_identifier_id,
        -- other fields --
    FROM {{ ref('source_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    GROUP BY base.event_id, attendee.email, attendee.is_optional, base.occurred_at
)
```

---

## 7. Edge Case Scenarios

### Composite Key Tests

If you see failures in edge tests like `nexus_group_identifiers_edges`, check
the test definition:

```yaml
# Wrong - array syntax doesn't work
tests:
  - unique:
      column_name: [edge_id, identifier_type_a, identifier_value_a]

# Correct - concatenated string syntax
tests:
  - unique:
      column_name: "edge_id || '|' || identifier_type_a || '|' || identifier_value_a || '|' || identifier_type_b || '|' || identifier_value_b"
```

### Performance Considerations

For large datasets with many duplicates:

1. **Fix highest-impact sources first** (those with most duplicates)
2. **Use LIMIT in diagnostic queries** to avoid timeouts
3. **Consider incremental rebuilds** for large models

---

## 8. Common Error Messages and Solutions

| Error Pattern            | Likely Cause                      | Solution                             |
| ------------------------ | --------------------------------- | ------------------------------------ |
| `Got 2000+ results`      | Missing role in ID generation     | Add role to `create_nexus_id` call   |
| `Got 1-10 results`       | Duplicate source data             | Add deduplication with `GROUP BY`    |
| `Edge test failing`      | Wrong test syntax                 | Use concatenated string syntax       |
| `Participant duplicates` | Missing role in participant macro | Update `finalize_participants` macro |

For additional help, see the [Testing Reference](../tests/index.md) for detailed
information about all available tests.
