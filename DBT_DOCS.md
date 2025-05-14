# Headless CRM dbt Package

## Overview

The Headless CRM dbt package provides a reusable implementation of a
source-independent customer data platform with identity resolution. This package
enables you to:

- Build a unified customer data platform from multiple data sources
- Resolve person and group identities across systems
- Maintain relationships between persons and groups
- Support real-time and batch processing workflows

The architecture follows the design outlined in the original Headless CRM
implementation but packaged for reuse across different projects with different
data sources and data warehouses.

## Package Architecture

```
dbt-headless-crm/
├── dbt_project.yml
├── models/
│   ├── event-log/          # Core event log models
│   │   ├── events.sql
│   │   ├── person_identifiers.sql
│   │   ├── person_traits.sql
│   │   ├── group_identifiers.sql
│   │   ├── group_traits.sql
│   │   └── membership_identifiers.sql
│   ├── identity-resolution/ # Identity resolution models
│   │   ├── persons/
│   │   │   ├── resolved_person_identifiers.sql
│   │   │   └── resolved_person_traits.sql
│   │   └── groups/
│   │       ├── resolved_group_identifiers.sql
│   │       └── resolved_group_traits.sql
│   └── final-tables/       # Production-ready models
│       ├── persons.sql
│       ├── groups.sql
│       ├── memberships.sql
│       └── links/
├── macros/
│   ├── real_time_event_filter.sql
│   ├── unpivot_identifiers.sql
│   ├── common_event_fields.sql
│   ├── get_first_or_last_row.sql
│   ├── unpivot_traits.sql
│   ├── directives.sql
│   ├── identity-resolution/
│   ├── pivot_identifiers.sql
│   ├── pivot_traits.sql
│   └── union_with_watermarks.sql
├── README.md
└── integration_tests/      # Test implementation with sample data
```

### Core Components

1. **Event Log Layer**: Standardized models for events, identifiers, and traits
2. **Identity Resolution Layer**: Logic to resolve identities and deduplicate
   entities
3. **Final Tables Layer**: Production-ready models with resolved entities
4. **Utility Macros**: Reusable components for transformation logic

## Implementation Strategy

### 1. Source Independence

The package is designed to be source-independent, allowing users to connect
their own data sources via adapter models. The package defines a clear interface
that source adapters must implement.

Configuration is done in the user's `dbt_project.yml`:

```yaml
vars:
  headless_crm:
    sources:
      - name: shopify_partner
        events_model: "ref('shopify_partner_events')"
        group_identifiers_model: "ref('shopify_partner_group_identifiers')"
        group_traits_model: "ref('shopify_partner_group_traits')"
      - name: gadget
        events_model: "ref('gadget_events')"
        group_identifiers_model: "ref('gadget_group_identifiers')"
        person_identifiers_model: "ref('gadget_person_identifiers')"
        membership_identifiers_model: "ref('gadget_membership_identifiers')"
```

### 2. Cross-Database Compatibility

The package supports multiple data warehouses by:

1. Using database-agnostic SQL patterns where possible
2. Leveraging dbt's `adapter.dispatch()` for database-specific implementations
3. Supporting Snowflake, BigQuery, and other major data warehouses

Example macro with database-specific implementations:

```sql
{% macro generate_surrogate_key(field_list) %}
  {{ return(adapter.dispatch('generate_surrogate_key', 'headless_crm')(field_list)) }}
{% endmacro %}

{% macro default__generate_surrogate_key(field_list) %}
  -- Snowflake implementation
  {{ dbt_utils.surrogate_key(field_list) }}
{% endmacro %}

{% macro bigquery__generate_surrogate_key(field_list) %}
  -- BigQuery implementation
  {{ dbt_utils.surrogate_key(field_list) }}
{% endmacro %}
```

### 3. Naming Conventions

All models and macros in the package follow these naming conventions:

1. **Package Prefix**: Models use the `headless_crm_` prefix to avoid namespace
   collisions
2. **Consistent Patterns**:
   - Core events: `headless_crm_events`
   - Person entities: `headless_crm_person_*`
   - Group entities: `headless_crm_group_*`
   - Resolved entities: `headless_crm_resolved_*`
3. **Schema Organization**: Models are organized into logical schemas using
   dbt's schema configuration

## User Implementation Guide

### 1. Installation

Add the package to your `packages.yml`:

```yaml
packages:
  - package: username/headless_crm
    version: 1.0.0
```

Install the package:

```bash
dbt deps
```

### 2. Source Adapter Implementation

Create source adapter models that follow the required interface:

```sql
-- models/sources/shopify/shopify_events.sql
{{ config(materialized='view') }}

SELECT
  id,
  occurred_at,
  event_name,
  event_description,
  value,
  value_unit,
  event_type,
  'shopify' as source,
  -- Other fields
  {{ current_timestamp() }} as _ingested_at
FROM {{ source('shopify', 'events') }}
```

Key requirements for source adapters:

- **Events Models**: Must include standard fields (id, occurred_at, event_name,
  etc.)
- **Identifier Models**: Must include appropriate identifier fields and types
- **Traits Models**: Must include trait name-value pairs with event attribution
- **Relationship Models**: Must define connections between persons and groups

### 3. Package Configuration

Configure the package in your `dbt_project.yml`:

```yaml
vars:
  headless_crm:
    sources:
      - name: shopify
        events_model: "ref('shopify_events')"
        group_identifiers_model: "ref('shopify_group_identifiers')"
        group_traits_model: "ref('shopify_group_traits')"
      - name: manual
        events_model: "ref('manual_events')"
        person_identifiers_model: "ref('manual_person_identifiers')"
        person_traits_model: "ref('manual_person_traits')"
        group_identifiers_model: "ref('manual_group_identifiers')"
        group_traits_model: "ref('manual_group_traits')"
        membership_identifiers_model: "ref('manual_membership_identifiers')"

    # Optional configurations
    incremental_strategy: "merge"
    id_resolution_window_days: 30
    override_incremental: false # Set to true for full refresh in dev
```

### 4. Building the Models

Run the package models:

```bash
# Run the entire package
dbt run --select headless_crm.*

# Or run individual layers
dbt run --select headless_crm.event_log
dbt run --select headless_crm.identity_resolution
dbt run --select headless_crm.final_tables
```

## Source Adapter Specifications

### Events Model

Required fields:

- `id` (string): Unique identifier for the event
- `occurred_at` (timestamp): When the event occurred
- `event_name` (string): Specific event name
- `event_description` (string): Human-readable description
- `value` (numeric, optional): Numeric value associated with the event
- `value_unit` (string, optional): Unit of the value field
- `event_type` (string): Category of the event
- `source` (string): The source system that generated the event
- `_ingested_at` (timestamp): When the record was processed

### Person/Group Identifiers Model

Required fields:

- `id` (string): Unique identifier for this identifier record
- `event_id` (string): Reference to the source event
- `row_id` (string): Surrogate key that groups related identifiers from the same
  record/entity
- `identifier_type` (string): Type of identifier (e.g., 'email', 'phone',
  'domain')
- `identifier_value` (string): The actual identifier value
- `source` (string): Source system
- `occurred_at` (timestamp): When this identifier was collected
- `_ingested_at` (timestamp): When the record was processed

### Person/Group Traits Model

Required fields:

- `id` (string): Unique identifier for this trait record
- `event_id` (string): Reference to the source event
- `row_id` (string): Groups related traits from the same record
- `trait_name` (string): Name of the trait/attribute
- `trait_value` (string): Value of the trait
- `source` (string): Source system
- `occurred_at` (timestamp): When this trait was collected
- `_ingested_at` (timestamp): When the record was processed

### Membership Identifiers Model

Required fields:

- `id` (string): Unique identifier for this membership record
- `event_id` (string): Reference to the source event
- `person_identifier` (string): Person identifier value
- `person_identifier_type` (string): Person identifier type (e.g., 'email')
- `group_identifier` (string): Group identifier value
- `group_identifier_type` (string): Group identifier type (e.g., 'domain')
- `role` (string, optional): Role of the person in the group
- `source` (string): Source system
- `occurred_at` (timestamp): When this membership was established
- `_ingested_at` (timestamp): When the record was processed

## Testing & Documentation

### Integration Testing

The package includes integration tests in the `integration_tests/` directory:

1. **Sample Data**: Seeds with test data for different sources
2. **Test Models**: Implementation of source adapters for testing
3. **Assertions**: Tests to validate the output of the package models

Run the integration tests:

```bash
cd integration_tests
dbt seed
dbt run
dbt test
```

### Package Documentation

The package includes comprehensive documentation:

1. **README.md**: Overview, installation, and basic usage
2. **docs/**: Detailed implementation guides
3. **Model Documentation**: Using dbt's built-in documentation

View the documentation:

```bash
dbt docs generate
dbt docs serve
```

## Versioning & Maintenance

The package follows semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes to interfaces or behavior
- **MINOR**: New features, non-breaking changes
- **PATCH**: Bug fixes, performance improvements

Migration guides will be provided for major version updates.

## Code Refactoring Recommendations

Before converting the current implementation into a package, we recommend the
following refactoring to make the codebase simpler, more maintainable, and
DRYer:

### 1. Standardize Source Adapters with Templates

Create template macros that source adapters can extend:

```sql
-- macros/generate_source_adapter.sql
{% macro generate_events_adapter(source_name, source_table) %}
  SELECT
    id,
    occurred_at,
    event_name,
    event_description,
    value,
    value_unit,
    event_type,
    '{{ source_name }}' as source,
    {{ current_timestamp() }} as _ingested_at
  FROM {{ source(source_name, source_table) }}
{% endmacro %}
```

Then source implementers can simply:

```sql
-- models/sources/shopify/shopify_events.sql
{{ config(materialized='view') }}

{{ generate_events_adapter('shopify', 'events') }}
```

### 2. Consolidate Identifier and Trait Processing

Create unified macros for processing identifiers and traits that work across
entity types:

```sql
-- macros/process_identifiers.sql
{% macro process_identifiers(entity_type, source_model) %}
  WITH unpivoted AS (
    {{ unpivot_identifiers(entity_type, source_model) }}
  ),

  normalized AS (
    -- Standardize identifier formats (lowercase emails, formatted phone numbers)
    SELECT
      *,
      CASE
        WHEN identifier_type = 'email' THEN LOWER(identifier_value)
        WHEN identifier_type = 'phone' THEN {{ normalize_phone(identifier_value) }}
        ELSE identifier_value
      END as normalized_value
    FROM unpivoted
  )

  SELECT * FROM normalized
{% endmacro %}
```

### 3. Create Entity-Agnostic Identity Resolution

Refactor the identity resolution code to work with any entity type:

```sql
-- macros/resolve_identities.sql
{% macro resolve_identities(entity_type, identifiers_model) %}
  WITH identifiers AS (
    SELECT * FROM {{ ref(identifiers_model) }}
  ),

  -- Generate edges between identifiers
  edges AS (
    {{ create_and_dedup_edges('identifiers', 'row_id') }}
  ),

  -- Perform connected component analysis
  connected_components AS (
    {{ find_connected_components('edges') }}
  )

  -- Final resolved identities
  SELECT
    {{ generate_surrogate_key(['component_id']) }} as {{ entity_type }}_id,
    identifier_type,
    identifier_value,
    source,
    occurred_at
  FROM connected_components
{% endmacro %}
```

### 4. Create a Unified Union Model Generator

Replace multiple union models with a single macro:

```sql
-- macros/generate_union_model.sql
{% macro generate_union_model(model_type, source_list_var) %}
  {% set sources = var(source_list_var) %}

  WITH {% for source in sources %}
    {{ source.name }}_data AS (
      SELECT * FROM {{ ref(source.name + '_' + model_type) }}
      {% if is_incremental() %}
      WHERE _ingested_at > (
        SELECT MAX(_ingested_at) FROM {{ this }}
        WHERE source = '{{ source.name }}'
      )
      {% endif %}
    ){% if not loop.last %},{% endif %}
  {% endfor %}

  {% for source in sources %}
    SELECT * FROM {{ source.name }}_data
    {% if not loop.last %}UNION ALL{% endif %}
  {% endfor %}
{% endmacro %}
```

Then in the models:

```sql
-- models/event-log/events.sql
{{ config(materialized='incremental', unique_key='id') }}

{{ generate_union_model('events', 'event_sources') }}
```

### 5. Create Unified Tests

Standardize tests across entity types:

```yaml
# models/event-log/schema.yml
version: 2

models:
  - name: events
    columns:
      - name: id
        tests:
          - not_null
          - unique
      - name: occurred_at
        tests:
          - not_null

  - name: person_identifiers
    columns:
      - name: id
        tests:
          - not_null
          - unique
      - name: event_id
        tests:
          - not_null
          - relationships:
              to: ref('events')
              field: id
```

### 6. Simplify Configuration with a Standard Structure

Create a more structured configuration pattern in dbt_project.yml:

```yaml
vars:
  headless_crm:
    entities:
      - name: person
        has_identifiers: true
        has_traits: true
      - name: group
        has_identifiers: true
        has_traits: true
    sources:
      - name: shopify
        supports_entities: [group]
        models:
          events: shopify_events
          group_identifiers: shopify_group_identifiers
          group_traits: shopify_group_traits
      - name: manual
        supports_entities: [person, group]
        models:
          events: manual_events
          person_identifiers: manual_person_identifiers
          person_traits: manual_person_traits
          group_identifiers: manual_group_identifiers
          group_traits: manual_group_traits
```

### 7. Create a Materialization Pipeline Manager

Add a macro to handle running model groups in the correct order:

```sql
-- macros/run_pipeline.sql
{% macro run_pipeline(entity_type) %}
  {% set models = [] %}

  {# Add event log models #}
  {% do models.append('event-log/' + entity_type + '_identifiers') %}
  {% do models.append('event-log/' + entity_type + '_traits') %}

  {# Add identity resolution models #}
  {% do models.append('identity-resolution/' + entity_type + 's/resolved_' + entity_type + '_identifiers') %}
  {% do models.append('identity-resolution/' + entity_type + 's/resolved_' + entity_type + '_traits') %}

  {# Add final table #}
  {% do models.append('final-tables/' + entity_type + 's') %}

  {{ return(models) }}
{% endmacro %}
```

### 8. Implement Cross-Database Type Handling

Create database-specific type handling:

```sql
-- macros/database_types.sql
{% macro get_json_field(column, field) %}
  {{ return(adapter.dispatch('get_json_field', 'headless_crm')(column, field)) }}
{% endmacro %}

{% macro default__get_json_field(column, field) %}
  -- Snowflake implementation
  {{ column }}:{{ field }}::string
{% endmacro %}

{% macro bigquery__get_json_field(column, field) %}
  -- BigQuery implementation
  JSON_EXTRACT_SCALAR({{ column }}, '$.{{ field }}')
{% endmacro %}
```

### 9. Consolidate Temporal Logic

Create utilities for time-based operations:

```sql
-- macros/temporal_helpers.sql
{% macro get_latest_value(table, partition_by, order_by) %}
  SELECT * FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY {{ partition_by }}
        ORDER BY {{ order_by }} DESC
      ) as row_num
    FROM {{ table }}
  )
  WHERE row_num = 1
{% endmacro %}
```

## Next Steps

To convert the current implementation into a package:

1. Refactor current models to use package naming convention
2. Extract core models from source-specific logic
3. Create source adapter specifications
4. Implement cross-database compatibility
5. Set up integration testing environment
6. Write package documentation
7. Publish initial version to dbt Hub
