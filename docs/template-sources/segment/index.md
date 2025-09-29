---
title: Segment Template Source
tags: [template-sources, segment, configuration, attribution]
summary:
  Ready-to-use Segment integration for events, person identifiers, person
  traits, and attribution touchpoints
---

# Segment Template Source

The Segment template source provides a complete integration for Segment
analytics data, enabling event tracking, person identification, and attribution
analysis within the dbt-nexus framework.

## Overview

This template source processes Segment data from three main event types:

- **Tracks**: User actions and custom events
- **Pages**: Page views and navigation events
- **Identifies**: User identification and trait updates

## Features

- ✅ **Event Processing**: Unified event tracking across all Segment event types
- ✅ **Person Identification**: Multi-identifier person resolution
- ✅ **Person Traits**: User attribute and trait management
- ✅ **Attribution Analysis**: UTM parameter and click ID tracking
- ✅ **Touchpoint Modeling**: Attribution touchpoint identification

## Configuration

### Basic Configuration

Enable the Segment template source in your `dbt_project.yml`:

```yaml
vars:
  nexus:
    segment:
      enabled: true
```

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
```

**Note**: Unlike other template sources, Segment requires explicit configuration
of both `database` and `schema` as there are no universal defaults for Segment
implementations.

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

#### `segment_person_identifiers`

Person identifiers from all Segment event types.

**Key Fields:**

- `person_identifier_id`: Unique identifier record ID
- `event_id`: Reference to source event
- `identifier_type`: Type of identifier (segment_anonymous_id, user_id, email)
- `identifier_value`: Identifier value
- `occurred_at`: Timestamp when captured

#### `segment_person_traits`

Person traits and attributes from Segment events.

**Key Fields:**

- `person_trait_id`: Unique trait record ID
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
classification. Configure your internal domains in the nexus package
configuration:

```yaml
vars:
  # Global configuration for all template sources
  internal_domains:
    - "yourcompany.com"
    - "subsidiary.com"

  # Attribution-specific exclusions
  referral_exclusions:
    - "%yourcompany.com%"
    - "%subsidiary.com%"
```

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
join {{ ref('segment_person_identifiers') }} pi
    on e.event_id = pi.event_id
where pi.identifier_type = 'user_id'
    and pi.identifier_value = 'user_123'
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

- Ensure `nexus.segment.enabled: true` in your project configuration
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

## Migration from Legacy Sources

If migrating from a legacy Segment source implementation:

1. **Backup Current Implementation**: Save existing models and tests
2. **Enable Template Source**: Set `nexus.segment.enabled: true`
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
