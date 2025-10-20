---
title: Segment Template Source
tags: [template-sources, segment, configuration, attribution, v0.3.0]
summary:
  Ready-to-use Segment integration for events, entity identifiers, entity
  traits, and attribution touchpoints with v0.3.0 entity-centric architecture
---

# Segment Template Source

The Segment template source provides a complete integration for Segment
analytics data, enabling event tracking, entity identification, and attribution
analysis within the dbt-nexus v0.3.0 entity-centric framework.

## Overview

This template source processes Segment data from three main event types:

- **Tracks**: User actions and custom events
- **Pages**: Page views and navigation events
- **Identifies**: User identification and trait updates

## Features

- ✅ **Event Processing**: Unified event tracking across all Segment event types
- ✅ **Entity Identification**: Multi-identifier entity resolution (person
  entities)
- ✅ **Entity Traits**: User attribute and trait management
- ✅ **Attribution Analysis**: UTM parameter and click ID tracking
- ✅ **Touchpoint Modeling**: Attribution touchpoint identification
- ✅ **v0.3.0 Compatible**: Entity-centric architecture with unified entity
  models

## Configuration

### Basic Configuration

Enable the Segment template source in your `dbt_project.yml`:

```yaml
vars:
  nexus:
    sources:
      segment:
        enabled: true
        events: true
        entities: ["person"]
        attribution: true # If using touchpoints
    segment: # Keep for backward compatibility with unpivot macros
      identifiers: ["email", "user_id"] # Optional: specify custom identifiers
      traits: ["name", "company"] # Optional: specify custom traits
```

### Multiple Segment Sources

When you have multiple Segment sources (e.g., different schemas or databases),
you need to create a `segment_sources.yml` file in your project to define all
sources:

**1. Create `models/sources/segment/segment_sources.yml`:**

```yaml
version: 2

sources:
  - name: WORDPRESS_SITE
    description: "WordPress site Segment data"
    database: DEV_RAW
    schema: WORDPRESS_SITE
    tables:
      - name: TRACKS
        description: "Segment track events"
      - name: PAGES
        description: "Segment page events"
      - name: IDENTIFIES
        description: "Segment identify events"
      - name: APPOINTMENT_FORM_SUBMITTED
        description: "Appointment form submission events"

  - name: SERVER_AWS_LAMBDA_TRACKING
    description: "Server AWS Lambda tracking Segment data"
    database: DEV_RAW
    schema: SERVER_AWS_LAMBDA_TRACKING
    tables:
      - name: TRACKS
        description: "Segment track events"
      - name: PAGES
        description: "Segment page events"
      - name: IDENTIFIES
        description: "Segment identify events"
      - name: NEW_LEAD_WEBSITE
        description: "New lead website events"
```

**2. Configure `segment_sources` in your `dbt_project.yml`:**

```yaml
vars:
  # Segment sources configuration for union_segment_sources macro
  segment_sources:
    - name: WORDPRESS_SITE
      tracks:
        - name: APPOINTMENT_FORM_SUBMITTED
          conversion: true
    - name: SERVER_AWS_LAMBDA_TRACKING
      tracks:
        - name: NEW_LEAD_WEBSITE
          conversion: true
```

**Why This Setup?**

- The `segment_sources.yml` defines the actual database sources that dbt can
  reference
- The `segment_sources` variable tells the `union_segment_sources` macro which
  sources to union and which specific track tables to include
- This allows you to have different table structures across different Segment
  sources while still unioning them together

### Advanced Configuration

```yaml
vars:
  nexus:
    segment:
      enabled: true
      location:
        database: DEV_RAW
        schema: WORDPRESS_SITE
        tables:
          tracks: TRACKS
          pages: PAGES
          identifies: IDENTIFIES
      capabilities:
        events: true
        persons: true
        groups: false
        memberships: false
        attribution: true
      # Configure which identifiers and traits to extract from identify events
      identifiers:
        - segment_anonymous_id
        - user_id
        - email
      traits:
        - segment_anonymous_id
        - user_id
        - email
        - first_name
```

**Note**: Unlike other template sources, Segment requires explicit configuration
of both `database` and `schema` as there are no universal defaults for Segment
implementations.

**Configurable Traits**: The `identifiers` and `traits` arrays allow you to
specify which fields to extract from Segment identify events, making the
template source adaptable to different Segment implementations.

### Customizing Identifiers and Traits

If your Segment implementation doesn't include certain fields (like
`first_name`), you can customize the configuration:

```yaml
vars:
  nexus:
    segment:
      enabled: true
      # ... other configuration ...
      identifiers:
        - segment_anonymous_id
        - user_id
        - email
        # Add custom identifiers as needed
      traits:
        - segment_anonymous_id
        - user_id
        - email
        # Remove first_name if not available
        # Add custom traits as needed
```

**Available Fields**: The template source supports these standard Segment
identify fields:

- `segment_anonymous_id` (from `anonymous_id`)
- `user_id`
- `email`
- `first_name`
- Custom traits as configured in your Segment implementation

## Data Sources

The template source dynamically references Segment data based on your
configuration. For the example configuration above, it expects:

| Table                               | Description                   | Required |
| ----------------------------------- | ----------------------------- | -------- |
| `DEV_RAW.WORDPRESS_SITE.TRACKS`     | Track events from Segment     | Yes      |
| `DEV_RAW.WORDPRESS_SITE.PAGES`      | Page view events from Segment | Yes      |
| `DEV_RAW.WORDPRESS_SITE.IDENTIFIES` | Identify events from Segment  | Yes      |

**Configuration Flexibility**: The actual table names are determined by your
`location` configuration, making the template source adaptable to any Segment
implementation structure.

### File Structure for Multiple Sources

When using multiple Segment sources, your project structure should look like:

```
models/
└── sources/
    └── segment/
        └── segment_sources.yml    # Your project-specific sources
dbt_packages/
└── nexus/
    └── models/
        └── sources/
            └── segment/
                └── segment.yml    # Nexus package sources (configurable)
```

**Important**: The nexus package's `segment.yml` remains configurable and should
not be modified. Your project-specific sources go in
`models/sources/segment/segment_sources.yml`.

## Models

### Core Models

#### `segment_events`

Unified events table containing all Segment event types (tracks, pages,
identifies).

**Key Fields:**

- `event_id`: Unique event identifier
- `occurred_at`: Event timestamp
- `event_type`: Type of event (web, identity)
- `event_name`: Specific event name
- `source`: Source system (segment)

#### `segment_entity_identifiers`

Entity identifiers from all Segment event types (person entities only).

**Key Fields:**

- `entity_identifier_id`: Unique identifier record ID
- `entity_type`: Entity type (always 'person' for Segment)
- `event_id`: Reference to source event
- `identifier_type`: Type of identifier (segment_anonymous_id, user_id, email)
- `identifier_value`: Identifier value
- `occurred_at`: Timestamp when captured

#### `segment_entity_traits`

Entity traits and attributes from Segment events (person entities only).

**Key Fields:**

- `entity_trait_id`: Unique trait record ID
- `entity_type`: Entity type (always 'person' for Segment)
- `event_id`: Reference to source event
- `trait_name`: Name of the trait
- `trait_value`: Trait value
- `occurred_at`: Timestamp when captured

### Attribution Models

#### `segment_touchpoints`

Attribution touchpoints with UTM parameters and click IDs.

**Key Fields:**

- `touchpoint_id`: Unique touchpoint identifier
- `source`: UTM source or campaign source
- `medium`: UTM medium or campaign medium
- `campaign`: UTM campaign or campaign name
- `channel`: Classified channel (paid, social, organic, referral, direct)
- `touchpoint_type`: Type of touchpoint (campaign, facebook_click, referral,
  direct)
- `fbclid`: Facebook click ID
- `gclid`: Google click ID

## Database Compatibility

The Segment template source is fully compatible with **Snowflake** and supports
the three-part naming convention (`database.schema.table`). It uses the
`nexus_source` macro for dynamic source resolution, making it adaptable to
different database structures.

### Snowflake Configuration

```yaml
vars:
  nexus:
    segment:
      enabled: true
      location:
        database: YOUR_DATABASE # Required for Snowflake
        schema: YOUR_SCHEMA # Required - no default
        tables:
          tracks: YOUR_TRACKS_TABLE
          pages: YOUR_PAGES_TABLE
          identifies: YOUR_IDENTIFIES_TABLE
```

## Attribution Configuration

The template source supports attribution analysis through UTM parameters and
click IDs:

### UTM Parameters

- `utm_source`: Traffic source
- `utm_medium`: Marketing medium
- `utm_campaign`: Campaign name
- `utm_content`: Content identifier
- `utm_term`: Keyword term

### Click IDs

- `fbclid`: Facebook click identifier
- `gclid`: Google Ads click identifier

### Channel Classification

Events are automatically classified into channels:

- **Paid**: UTM parameters present
- **Social**: Facebook referrer or fbclid present
- **Organic**: Google referrer present
- **Referral**: External referrer (excluding internal domains)
- **Direct**: No attribution information

### Referral Exclusions

The template source automatically excludes internal domains from referral
classification. Configure your internal domains in your project's
`dbt_project.yml`:

```yaml
vars:
  # Global configuration for all template sources
  internal_domains:
    - "yourcompany.com"
    - "subsidiary.com"

  # Attribution-specific exclusions (required for segment_touchpoints)
  referral_exclusions:
    - "%yourcompany.com%"
    - "%subsidiary.com%"
```

**Important**: The `referral_exclusions` variable is **required** for the
`segment_touchpoints` model to work properly. Without this configuration, you'll
get compilation errors like "NoneType object is not iterable" because the model
uses Jinja templating to iterate over these exclusions.

The exclusions use SQL `LIKE` operators with `%` wildcards to match any URL
containing your domain (including subdomains). For example, `%yourcompany.com%`
will exclude:

- `https://www.yourcompany.com`
- `https://blog.yourcompany.com/page`
- `https://yourcompany.com/landing-page`

## Usage Examples

### Enable Segment Integration

```yaml
# dbt_project.yml
vars:
  nexus:
    segment:
      enabled: true
```

### Query Attribution Data

```sql
-- Get attribution touchpoints
select
    touchpoint_id,
    source,
    medium,
    campaign,
    channel,
    touchpoint_type,
    occurred_at
from {{ ref('segment_touchpoints') }}
where occurred_at >= current_date - 30
order by occurred_at desc
```

### Analyze Person Journey

```sql
-- Get person events with identifiers
select
    e.event_name,
    e.occurred_at,
    pi.identifier_type,
    pi.identifier_value
from {{ ref('segment_events') }} e
join {{ ref('segment_entity_identifiers') }} pi
    on e.event_id = pi.event_id
where pi.identifier_type = 'user_id'
    and pi.identifier_value = 'user_123'
    and pi.entity_type = 'person'
order by e.occurred_at desc
```

## Testing

The template source includes comprehensive tests:

- **Uniqueness**: Event IDs, person identifier IDs, person trait IDs
- **Not Null**: Required fields validation
- **Accepted Values**: Event types, identifier types, trait names
- **Expression Tests**: ID format validation

Run tests with:

```bash
dbt test --select package:nexus segment
```

## Troubleshooting

### Common Issues

**Models Not Building**

- Ensure `nexus.sources.segment.enabled: true` in your project configuration
- Verify Segment source tables exist and are accessible
- Check that both `database` and `schema` are configured (no defaults for
  Segment)

**Compilation Errors**

- **"NoneType object is not iterable"**: Ensure `referral_exclusions` variable
  is configured in the nexus package
- **"Source not found"**: Verify table name casing matches your configuration
  (lowercase in YAML, uppercase in database)
- **"Schema does not exist"**: Check that the schema name in your configuration
  matches your actual database schema
- **"Source named 'X.Y' which was not found"**: For multiple segment sources,
  ensure you have created `models/sources/segment/segment_sources.yml` with all
  your segment sources defined
- **"union_segment_sources macro error"**: Verify that your `segment_sources`
  variable in `dbt_project.yml` matches the source names in your
  `segment_sources.yml` file

**Missing Attribution Data**

- Check that UTM parameters are being sent in Segment events
- Verify referrer exclusions are configured correctly
- Ensure `referral_exclusions` variable is defined to prevent compilation errors

**Person Resolution Issues**

- Ensure person identifiers are being captured in Segment
- Check that anonymous_id and user_id are being sent consistently

**Snowflake-Specific Issues**

- Verify three-part naming convention: `database.schema.table`
- Check that the `database` parameter is set in your configuration
- Ensure table names match your actual Snowflake table names (case-sensitive)

### Debug Queries

```sql
-- Check event data availability
select
    event_type,
    count(*) as event_count,
    min(occurred_at) as earliest_event,
    max(occurred_at) as latest_event
from {{ ref('segment_events') }}
group by event_type

-- Check attribution data
select
    channel,
    touchpoint_type,
    count(*) as touchpoint_count
from {{ ref('segment_touchpoints') }}
group by channel, touchpoint_type
```

## v0.3.0 Entity-Centric Migration

The Segment template source has been updated for dbt-nexus v0.3.0 with
entity-centric architecture:

### Key Changes

- **Model Names**: `segment_person_identifiers` → `segment_entity_identifiers`
- **Model Names**: `segment_person_traits` → `segment_entity_traits`
- **Field Names**: `person_identifier_id` → `entity_identifier_id`
- **Field Names**: `person_trait_id` → `entity_trait_id`
- **New Field**: `entity_type` (always 'person' for Segment)
- **Configuration**: `nexus.segment.enabled` → `nexus.sources.segment.enabled`

### Migration Steps

1. **Update Configuration**: Change to new `nexus.sources.segment` structure
2. **Update References**: Update any custom models referencing old model names
3. **Add Entity Type Filtering**: Add `entity_type = 'person'` to queries if
   needed
4. **Test Migration**: Run
   `dbt run --select segment_entity_identifiers segment_entity_traits`

### Backward Compatibility

The `nexus.segment` configuration namespace is preserved for the unpivot macros,
so existing identifier and trait configurations continue to work.

### Architecture Notes

Unlike other template sources (Gmail, Google Calendar), Segment uses a
simplified architecture:

- **No intermediate/union layers**: Direct entity models without four-layer
  structure
- **Person-only entities**: `entity_type='person'` is hardcoded (no groups)
- **No relationships**: Segment doesn't track entity-to-entity relationships
- **Simplified structure**: Maintains Segment's flat, straightforward approach

## Migration from Legacy Sources

If migrating from a legacy Segment source implementation:

1. **Backup Current Implementation**: Save existing models and tests
2. **Enable Template Source**: Set `nexus.sources.segment.enabled: true`
3. **Test Migration**: Run `dbt run --select package:nexus segment`
4. **Update References**: Update any custom models referencing old source models
5. **Remove Legacy Files**: Delete old Segment source files

## Technical Implementation

### Dynamic Source Resolution

The Segment template source uses the `nexus_source` macro for dynamic source
resolution:

```sql
-- Base models use the nexus_source macro
select * from {{ nexus_source('segment', 'tracks') }}
select * from {{ nexus_source('segment', 'pages') }}
select * from {{ nexus_source('segment', 'identifies') }}
```

This macro automatically resolves to the correct database.schema.table structure
based on your configuration.

### Jinja Templating

The source definitions use Jinja templating for complete configurability:

```yaml
sources:
  - name:
      "{{ var('nexus', {}).get('segment', {}).get('location', {}).get('schema')
      }}"
    database:
      "{{ var('nexus', {}).get('segment', {}).get('location',
      {}).get('database', '') }}"
    tables:
      - name:
          "{{ var('nexus', {}).get('segment', {}).get('location',
          {}).get('tables', {}).get('tracks', 'TRACKS') }}"
```

### Error Prevention

The template source includes several error prevention measures:

- **Referral Exclusions**: Prevents `NoneType` iteration errors by requiring
  `referral_exclusions` configuration
- **No Hardcoded Defaults**: Forces explicit configuration to prevent
  assumptions about Segment implementations
- **Case Sensitivity**: Handles table name casing correctly for different
  database systems

## Best Practices

1. **Consistent Naming**: Use consistent event names in Segment
2. **UTM Parameters**: Always include UTM parameters for campaign tracking
3. **Person Identification**: Send both anonymous_id and user_id consistently
4. **Data Quality**: Monitor for missing or invalid timestamps
5. **Attribution**: Configure referrer exclusions for internal domains
6. **Configuration**: Always specify both `database` and `schema` (no defaults
   for Segment)
7. **Testing**: Test compilation before running models to catch configuration
   issues early

## Support

For issues or questions:

- Check the [troubleshooting guide](../../explanations/troubleshooting.md)
- Review existing implementations in other client projects
- Consult the [Segment documentation](https://segment.com/docs/)

---

**Ready to get started?** Enable the Segment template source in your project
configuration and run `dbt run --select package:nexus segment` to begin
processing your Segment data.
