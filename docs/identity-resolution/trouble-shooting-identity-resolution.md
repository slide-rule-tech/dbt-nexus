# Troubleshooting Identity Resolution

## Common Issues and Solutions

### 1. Missing Identifiers in Source Models

**Problem**: Records that should be merged are not being resolved to the same
entity ID, even though they share common identifiers like email.

**Root Cause**: One or more source models are missing the shared identifier in
their entity identifier models, preventing the identity resolution process from
connecting records across systems.

**Example**:

- Gmail source includes `email` in both identifiers and traits
- Notion source includes `email` in traits but NOT in identifiers
- Result: Records with the same email get different entity IDs because they
  can't be connected during identity resolution

**Solution**: Ensure all source models that should share identity resolution
include the same identifiers in their `*_entity_identifiers` models.

**Check**: Review your source model files (e.g., `*_entity_identifiers.sql`) to
ensure they include all the identifiers you expect to use for identity
resolution.

## Debugging Methods

### 1. Check for Duplicate Emails in Final Table

```sql
-- Check if the same email appears with multiple person IDs
SELECT
  email,
  COUNT(DISTINCT entity_id) as unique_entity_ids,
  COUNT(*) as total_records,
  STRING_AGG(DISTINCT entity_id, ', ') as entity_ids
FROM {{ ref('nexus_entities') }}
WHERE email IS NOT NULL
  AND email != ''
  AND entity_type = 'person'
GROUP BY email
HAVING COUNT(DISTINCT entity_id) > 1
ORDER BY unique_entity_ids DESC
LIMIT 10
```

### 2. Verify Identity Resolution is Working

```sql
-- Check if emails are properly resolved to single entity IDs
SELECT
  identifier_value as email,
  COUNT(DISTINCT person_id) as unique_person_ids,
  STRING_AGG(DISTINCT person_id, ', ') as person_ids
FROM {{ ref('nexus_resolved_person_identifiers') }}
WHERE identifier_type = 'email'
GROUP BY identifier_value
HAVING COUNT(DISTINCT person_id) > 1
ORDER BY unique_person_ids DESC
LIMIT 10
```

### 3. Debug Specific Records

Create development models to investigate specific cases:

```sql
-- models/development/entity_identifiers_debug.sql
SELECT * FROM {{ ref('nexus_resolved_person_identifiers') }}
WHERE identifier_value = 'problematic@email.com'
```

```sql
-- models/development/entities_debug.sql
SELECT * FROM {{ ref('nexus_entities') }}
WHERE email = 'problematic@email.com'
  AND entity_type = 'person'
```

### 4. Check Source Model Identifier Coverage

```sql
-- Check what identifiers each source is contributing by entity type
SELECT
  source,
  entity_type,
  identifier_type,
  COUNT(*) as count,
  COUNT(DISTINCT identifier_value) as unique_values
FROM {{ ref('nexus_entity_identifiers') }}
GROUP BY source, entity_type, identifier_type
ORDER BY source, entity_type, count DESC
```

### 5. Verify Trait Resolution

```sql
-- Check if traits are being resolved correctly
SELECT
  entity_id,
  entity_type,
  trait_name,
  trait_value
FROM {{ ref('nexus_resolved_entity_traits') }}
WHERE entity_id IN ('ent_abc123...', 'ent_def456...')
  AND trait_name IN ('email', 'name', 'domain')
ORDER BY entity_id, trait_name
```

## Check Your Input Data

### 1. Verify Source Identifiers Exist

```sql
-- Check source entity identifiers (e.g., Gmail)
SELECT
    source,
    entity_type,
    identifier_type,
    COUNT(*) as count
FROM {{ ref('gmail_entity_identifiers') }}
GROUP BY source, entity_type, identifier_type;
```

Expected: Identifiers for both entity types with multiple identifier types per
entity

### 2. Verify Identifiers Made It to Nexus Core

```sql
-- Check nexus_entity_identifiers
SELECT
    source,
    entity_type,
    identifier_type,
    COUNT(*) as count
FROM {{ ref('nexus_entity_identifiers') }}
GROUP BY source, entity_type, identifier_type;
```

Expected: Your source identifiers should appear here with the same counts for
each entity type

### 3. Check Edge Creation

```sql
-- Check nexus_entity_identifiers_edges
SELECT
    entity_type,
    identifier_type_a,
    identifier_type_b,
    COUNT(*) as edge_count
FROM {{ ref('nexus_entity_identifiers_edges') }}
WHERE entity_type = 'person'  -- or 'group'
GROUP BY entity_type, identifier_type_a, identifier_type_b;
```

Expected: Edges connecting different identifier types for each entity type

### 4. Check Resolution Output

```sql
-- Check resolved identifiers
SELECT
    identifier_type,
    COUNT(DISTINCT identifier_value) as distinct_values,
    COUNT(DISTINCT person_id) as unique_persons
FROM {{ ref('nexus_resolved_person_identifiers') }}
GROUP BY identifier_type;
```

Expected: Multiple distinct values collapsing into fewer unique entities

## Key Files to Check

1. **Source Identifier Models**:
   `models/sources/*/intermediate/*_person_identifiers.sql`
   `models/sources/*/intermediate/*_group_identifiers.sql`
2. **Source Union Models**: `models/sources/*/{source}_entity_identifiers.sql`
3. **Nexus Core**: `nexus_entity_identifiers`
4. **Edges Table**: `nexus_entity_identifiers_edges` (unified for all entity
   types)
5. **Resolved Identifiers**: `nexus_resolved_person_identifiers`,
   `nexus_resolved_group_identifiers`
6. **Resolved Traits**: `nexus_resolved_entity_traits` (unified)
7. **Final Entities Table**: `nexus_entities` (unified with entity_type filter)

## Prevention

- Always include shared identifiers (email, phone, domain, etc.) in entity
  identifier models for each source
- Use development models to test identity resolution with specific records
- Regularly check for duplicate emails/domains in the final entities table
- Verify that `nexus_max_recursion` is set appropriately for your data
  complexity (recommend: 3 for large datasets)
- Ensure `entity_type` is included in edge uniqueness hash to prevent collisions
