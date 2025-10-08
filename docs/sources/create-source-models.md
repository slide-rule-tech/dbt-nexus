---
title: Generate Identity Resolution Models for New Sources
tags: [how-to, identity-resolution, models, sources]
summary:
  Complete guide for creating identifier and trait models when adding a new data
  source to the dbt-nexus identity resolution system.
---

When adding a new data source to your dbt-nexus project, you need to create a
set of identity resolution models that enable customer identity resolution. This
guide walks through the complete process of generating these models.

## Overview

The dbt-nexus identity resolution system requires **6 core model types** for
each new source:

1. **Events** - Core event data from the source
2. **Person Identifiers** - Individual identifiers (emails, phones, user IDs)
3. **Person Traits** - Characteristics and attributes of individuals
4. **Group Identifiers** - Group-level identifiers (domains, addresses, contract
   IDs)
5. **Group Traits** - Characteristics and attributes of groups
6. **Membership Identifiers** - Relationships between persons and groups

**Important**: You must create models for either **persons** (identifiers +
traits) or **groups** (identifiers + traits), but not necessarily both. However,
if you create both person and group models, you should also likely create
membership identifiers to link them together.

## Prerequisites

Before creating identity resolution models, ensure you have:

- A **staging model** that cleans and standardizes your source data
- Understanding of your source's **entity relationships**
- **dbt_project.yml configuration** updated to include your new source

**Recommended**: Review the
[Recommended Source Model Structure](recommend-source-model-structure.md) guide
for best practices on organizing your source models using a four-layer
architecture pattern.

## Step 1: Create Events Model

The events model captures the core event data from your source.

```sql
{{ config(tags=['identity-resolution','events'], materialized='table') }}

with source_data as (
    select * from {{ ref('stg_your_source') }}
),

events as (
    select
        -- Generate unique event ID
        {{ dbt_utils.generate_surrogate_key([
            'primary_key_field',
            'timestamp_field'
        ]) }} as event_id,

        -- Event metadata
        event_timestamp as occurred_at,
        'your_event_type' as event_type,
        'event_name' as event_name,
        'your_source' as source,

        -- Additional event data
        field1,
        field2,
        field3

    from source_data
    where event_timestamp is not null
)

select * from events
order by occurred_at desc
```

## Step 2: Create Person Identifiers Model

Person identifiers capture individual-level identifiers that can be used for
identity resolution.

```sql
{{ config(tags=['identity-resolution','persons'], materialized='table') }}

{{ nexus.unpivot_identifiers(
    model_name='stg_your_source',
    columns=['email', 'phone_number', 'user_id', 'customer_id'],
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'your_source' as source"],
    column_to_identifier_type={
      'email': 'email',
      'phone_number': 'phone',
      'user_id': 'user_id',
      'customer_id': 'customer_id'
    },
    role_column="'customer'",
    entity_type='person'
) }}

order by occurred_at desc
```

## Step 3: Create Person Traits Model

Person traits capture characteristics and attributes of individuals.

```sql
{{ config(tags=['identity-resolution','persons'], materialized='table') }}

{{ nexus.unpivot_traits(
    model_name='stg_your_source',
    columns=[
        'first_name',
        'last_name',
        'email',
        'phone_number',
        'age',
        'gender',
        'preferences'
    ],
    identifier_column='user_id',
    identifier_type='user_id',
    event_id_field='event_id',
    additional_columns=['occurred_at', "'your_source' as source"],
    column_to_trait_name={
        'first_name': 'first_name',
        'last_name': 'last_name'
    },
    entity_type='person'
) }}

order by occurred_at desc
```

## Step 4: Create Group Identifiers Model

Group identifiers capture group-level identifiers for householding and
organizational grouping.

```sql
{{ config(tags=['identity-resolution','groups'], materialized='table') }}

{{ nexus.unpivot_identifiers(
    model_name='stg_your_source',
    columns=['domain', 'address', 'company_id'],
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'your_source' as source"],
    column_to_identifier_type={
      'domain': 'domain',
      'address': 'address',
      'company_id': 'company_id'
    },
    role_column="'organization'",
    entity_type='group'
) }}

order by occurred_at desc
```

## Step 5: Create Group Traits Model

Group traits capture characteristics and attributes of groups.

```sql
{{ config(tags=['identity-resolution','groups'], materialized='table') }}

{{ nexus.unpivot_traits(
    model_name='stg_your_source',
    columns=[
        'company_name',
        'domain',
        'address',
        'city',
        'state',
        'zip_code',
        'industry'
    ],
    identifier_column='company_id',
    identifier_type='company_id',
    event_id_field='event_id',
    additional_columns=['occurred_at', "'your_source' as source"],
    column_to_trait_name={
        'company_name': 'name',
        'zip_code': 'postal_code'
    },
    entity_type='group'
) }}

order by occurred_at desc
```

## Step 6: Create Membership Identifiers Model

Membership identifiers capture relationships between persons and groups.

```sql
{{ config(tags=['identity-resolution','memberships'], materialized='table') }}

with source_data as (
    select * from {{ ref('stg_your_source') }}
),

membership_data as (
    select
        {{ dbt_utils.generate_surrogate_key(['event_id', 'user_id']) }} as event_id,
        {{ dbt_utils.generate_surrogate_key(['event_id', 'user_id']) }} as edge_id,
        occurred_at,
        'your_source' as source,

        -- Person identifier
        user_id as person_identifier,
        'user_id' as person_identifier_type,

        -- Group identifier
        company_id as group_identifier,
        'company_id' as group_identifier_type,

        -- Membership role
        'employee' as role

    from source_data
    where user_id is not null
    and company_id is not null
)

select * from membership_data
order by occurred_at desc
```

## Step 7: Configure dbt_project.yml

**Critical**: You must update your `dbt_project.yml` file to register your new
source with the nexus system. Without this configuration, nexus will not
recognize or process your new source.

```yaml
vars:
  nexus_max_recursion: 3
  sources:
    - name: your_source_name
      events: true
      persons: true # Set to true if you created person models
      groups: true # Set to true if you created group models
```

**Important**:

- The `name` field must match the source name used in your models
- Set `events`, `persons`, and `groups` to `true` based on which model types you
  created
- This configuration tells nexus which sources to include in the identity
  resolution pipeline

## Model Configuration Guidelines

### Tags

- Use `identity-resolution` tag for all identity resolution models
- Add specific tags: `events`, `persons`, `groups`, `memberships`

### Materialization

- Use `table` materialization for identity resolution models
- Consider `incremental` for very large sources

### Naming Conventions

- Use descriptive names: `{source}_{entity}_{type}.sql`
- Examples: `enrollments_person_identifiers.sql`, `contracts_group_traits.sql`

## Testing Your Models

After creating your identity resolution models:

1. **Compile and run** each model individually
2. **Check data quality** - ensure no null identifiers where expected
3. **Validate relationships** - verify membership identifiers link correctly
4. **Test identity resolution** - run the full identity resolution pipeline

## Common Patterns

### E-commerce Sources

- **Person identifiers**: email, customer_id, user_id
- **Group identifiers**: domain, shop_id
- **Membership roles**: customer, admin, staff

### CRM Sources

- **Person identifiers**: email, phone, contact_id
- **Group identifiers**: company_id, domain
- **Membership roles**: contact, lead, customer

### Event Tracking Sources

- **Person identifiers**: user_id, session_id, device_id
- **Group identifiers**: domain, app_id
- **Membership roles**: user, visitor, subscriber

## Troubleshooting

### Common Issues

**Null identifiers**: Ensure your staging model handles null values
appropriately **Duplicate events**: Use proper surrogate key generation
**Missing relationships**: Verify membership identifiers include all relevant
person-group pairs

### Performance Considerations

- **Index key fields** in your staging models
- **Filter early** - add where clauses to reduce data volume
- **Use incremental** materialization for large, frequently updated sources

## Next Steps

After creating your identity resolution models:

1. **Run the full identity resolution pipeline** to test the system
2. **Validate results** against known customer relationships
3. **Monitor performance** and optimize as needed
4. **Document your source** for future reference

For more advanced configuration options, see the
[Configuration Guide](getting-started/configuration.md).
