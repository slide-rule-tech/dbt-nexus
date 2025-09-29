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
        schema: SEGMENT_LIVE
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

## Data Sources

The template source expects Segment data in the following tables:

| Table                     | Description                   | Required |
| ------------------------- | ----------------------------- | -------- |
| `SEGMENT_LIVE.TRACKS`     | Track events from Segment     | Yes      |
| `SEGMENT_LIVE.PAGES`      | Page view events from Segment | Yes      |
| `SEGMENT_LIVE.IDENTIFIES` | Identify events from Segment  | Yes      |

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

**Missing Attribution Data**

- Check that UTM parameters are being sent in Segment events
- Verify referrer exclusions are configured correctly

**Person Resolution Issues**

- Ensure person identifiers are being captured in Segment
- Check that anonymous_id and user_id are being sent consistently

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

## Best Practices

1. **Consistent Naming**: Use consistent event names in Segment
2. **UTM Parameters**: Always include UTM parameters for campaign tracking
3. **Person Identification**: Send both anonymous_id and user_id consistently
4. **Data Quality**: Monitor for missing or invalid timestamps
5. **Attribution**: Configure referrer exclusions for internal domains

## Support

For issues or questions:

- Check the [troubleshooting guide](../../explanations/troubleshooting.md)
- Review existing implementations in other client projects
- Consult the [Segment documentation](https://segment.com/docs/)

---

**Ready to get started?** Enable the Segment template source in your project
configuration and run `dbt run --select package:nexus segment` to begin
processing your Segment data.
