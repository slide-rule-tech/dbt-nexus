# Troubleshooting Identity Resolution

## Common Issues and Solutions

### 1. Missing Identifiers in Source Models

**Problem**: Records that should be merged are not being resolved to the same
person ID, even though they share common identifiers like email.

**Root Cause**: One or more source models are missing the shared identifier in
their `unpivot_identifiers` macro call, preventing the identity resolution
process from connecting records across systems.

**Example**:

- Segment source includes `email` in both identifiers and traits
- Go High Level source includes `email` in traits but NOT in identifiers
- Result: Records with the same email get different person IDs because they
  can't be connected during identity resolution

**Solution**: Ensure all source models that should share identity resolution
include the same identifiers in their `unpivot_identifiers` macro calls.

**Check**: Review your source model files (e.g., `*_person_identifiers.sql`) to
ensure they include all the identifiers you expect to use for identity
resolution.

## Debugging Methods

### 1. Check for Duplicate Emails in Final Table

```sql
-- Check if the same email appears with multiple person IDs
SELECT
  email,
  COUNT(DISTINCT person_id) as unique_person_ids,
  COUNT(*) as total_records,
  LISTAGG(DISTINCT person_id, ', ') as person_ids
FROM {{ ref('nexus_persons') }}
WHERE email IS NOT NULL AND email != ''
GROUP BY email
HAVING COUNT(DISTINCT person_id) > 1
ORDER BY unique_person_ids DESC
LIMIT 10
```

### 2. Verify Identity Resolution is Working

```sql
-- Check if emails are properly resolved to single person IDs
SELECT
  IDENTIFIER_VALUE as email,
  COUNT(DISTINCT PERSON_ID) as unique_person_ids,
  LISTAGG(DISTINCT PERSON_ID, ', ') as person_ids
FROM {{ ref('nexus_resolved_person_identifiers') }}
WHERE IDENTIFIER_TYPE = 'email'
GROUP BY IDENTIFIER_VALUE
HAVING COUNT(DISTINCT PERSON_ID) > 1
ORDER BY unique_person_ids DESC
LIMIT 10
```

### 3. Debug Specific Records

Create development models to investigate specific cases:

```sql
-- models/development/person_identifiers.sql
select * from {{ ref('nexus_resolved_person_identifiers') }}
where identifier_value = 'problematic@email.com'
```

```sql
-- models/development/persons.sql
select * from {{ ref('nexus_persons') }}
where email = 'problematic@email.com'
```

### 4. Check Source Model Identifier Coverage

```sql
-- Check what identifiers each source is contributing
SELECT
  source,
  identifier_type,
  COUNT(*) as count,
  COUNT(DISTINCT identifier_value) as unique_values
FROM {{ ref('nexus_person_identifiers') }}
GROUP BY source, identifier_type
ORDER BY source, count DESC
```

### 5. Verify Trait Resolution

```sql
-- Check if traits are being resolved correctly
SELECT
  person_id,
  trait_name,
  trait_value
FROM {{ ref('nexus_resolved_person_traits') }}
WHERE person_id IN ('person_id_1', 'person_id_2')
  AND trait_name IN ('email', 'ghl_contact_id', 'segment_anonymous_id')
ORDER BY person_id, trait_name
```

## Key Files to Check

1. **Source Identifier Models**:
   `models/sources/*/intermediate/*_person_identifiers.sql`
2. **Source Trait Models**: `models/sources/*/intermediate/*_person_traits.sql`
3. **Resolved Identifiers**: `nexus_resolved_person_identifiers`
4. **Resolved Traits**: `nexus_resolved_person_traits`
5. **Final Persons Table**: `nexus_persons`

## Prevention

- Always include shared identifiers (email, phone, etc.) in BOTH the identifiers
  and traits for each source
- Use development models to test identity resolution with specific records
- Regularly check for duplicate emails in the final persons table
- Verify that `nexus_max_recursion` is set appropriately for your data
  complexity
