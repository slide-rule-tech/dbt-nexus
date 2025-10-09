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

The dbt-nexus identity resolution system requires **4 core model types** for
each new source:

1. **Events** - Core event data from the source
2. **Entity Identifiers** - Unified identifiers for all entity types (persons,
   groups, etc.)
3. **Entity Traits** - Unified characteristics and attributes for all entity
   types
4. **Relationship Declarations** - Relationships between entities (e.g.,
   person-to-group memberships)

**Important**: Each source model combines multiple entity types (person, group,
etc.) into unified tables with an `entity_type` field, rather than creating
separate models per entity type. This reduces model count by ~50% and simplifies
maintenance.

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

## Step 3: Create Entity Traits Model

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

## Step 4: Create Relationship Declarations Model

Relationship declarations capture relationships between entities (e.g.,
person-to-group memberships, person-to-task assignments, etc.).

```sql
{{ config(
    materialized='table',
    tags=['nexus', 'relationship_declarations', 'your_source']
) }}

with source_data as (
    select * from {{ ref('your_source_order_events') }}
),

customer_organization_relationships as (
    select
        {{ nexus.create_nexus_id('relationship_declaration', ['event_id', 'customer_email', 'company_domain']) }} as relationship_declaration_id,
        event_id,
        occurred_at,

        -- Entity A (person)
        customer_email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'customer' as entity_a_role,

        -- Entity B (group)
        company_domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,

        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'your_source' as source

    from source_data
    where customer_email is not null
      and company_domain is not null
)

select * from customer_organization_relationships
order by occurred_at desc
```

## Step 5: Configure dbt_project.yml

**Critical**: You must update your `dbt_project.yml` file to register your new
source with the nexus system. Without this configuration, nexus will not
recognize or process your new source.

```yaml
vars:
  nexus_max_recursion: 3
  nexus_entity_types: ["person", "group"] # Declare which entity types you're using

  sources:
    - name: your_source_name
      events: true
      entities: ["person", "group"] # List which entity types this source provides
      relationships: true # Set to true if you created relationship_declarations model
```

**Important**:

- The `name` field must match the source name used in your models
- `nexus_entity_types` declares all entity types across all sources (used for
  dynamic model generation)
- `entities` lists which entity types this specific source provides
- Set `relationships: true` if you created a relationship_declarations model
- This configuration tells nexus which sources to include in the identity
  resolution pipeline

## Model Configuration Guidelines

### Tags

- Use `nexus` tag for all nexus models
- Add specific tags: `events`, `entity_identifiers`, `entity_traits`,
  `relationship_declarations`

### Materialization

- Use `table` materialization for identity resolution models
- Consider `incremental` for very large sources

### Naming Conventions

- Use descriptive names: `{source}_{model_type}.sql`
- Required models:
  - `{source}_events.sql`
  - `{source}_entity_identifiers.sql`
  - `{source}_entity_traits.sql`
  - `{source}_relationship_declarations.sql`

## Testing Your Models

After creating your identity resolution models:

1. **Compile and run** each model individually
2. **Check data quality** - ensure no null identifiers where expected
3. **Validate entity_type field** - verify all identifiers/traits have
   entity_type set
4. **Validate relationships** - verify relationship declarations link correctly
5. **Test identity resolution** - run the full identity resolution pipeline

## Common Patterns

### E-commerce Sources

- **Person identifiers**: email, customer_id, user_id (entity_type='person')
- **Group identifiers**: domain, shop_id (entity_type='group')
- **Entity roles**: customer, admin, staff, organization
- **Relationships**: customer→shop memberships

### CRM Sources

- **Person identifiers**: email, phone, contact_id (entity_type='person')
- **Group identifiers**: company_id, domain (entity_type='group')
- **Entity roles**: contact, lead, customer, organization, account
- **Relationships**: contact→account memberships

### Event Tracking Sources

- **Person identifiers**: user_id, session_id, device_id (entity_type='person')
- **Group identifiers**: domain, app_id (entity_type='group')
- **Entity roles**: user, visitor, subscriber, organization
- **Relationships**: user→organization memberships (if applicable)

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
