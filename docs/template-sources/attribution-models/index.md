---
title: Attribution Models Template Source
tags: [template-sources, attribution-models, configuration, attribution]
summary:
  Ready-to-use attribution models for touchpoint attribution and conversion
  tracking within the dbt-nexus framework
---

# Attribution Models Template Source

The Attribution Models template source provides a collection of reusable
attribution models that can be enabled and configured to track how different
touchpoints contribute to conversions and events.

## Overview

Attribution models help you understand which marketing touchpoints are most
effective at driving conversions. The template source includes various
attribution models that can be enabled based on your needs.

## Available Models

### Last Facebook Click ID (`last_fbclid`)

Tracks the most recent Facebook click ID (fbclid) for each person across their
touchpoint journey. This model carries forward the last non-null fbclid for each
person, assigning it to all subsequent events until a new fbclid is encountered.

**Use Cases:**

- Facebook ad attribution
- Social media campaign tracking
- Cross-session attribution

**Key Features:**

- Window function-based attribution
- Person-level tracking
- Touchpoint batch processing
- 90-day attribution window

## Configuration

### Basic Configuration

Enable attribution models in your `dbt_project.yml`:

```yaml
vars:
  nexus:
    attribution_models:
      last_fbclid:
        enabled: true
```

### Advanced Configuration

```yaml
vars:
  nexus:
    attribution_models:
      last_fbclid:
        enabled: true
        attribution_window_days: 90
        touchpoint_types: ["facebook_click", "campaign"]
```

## Model Schema

### `last_fbclid`

**Output Fields:**

| Field                          | Type      | Description                           |
| ------------------------------ | --------- | ------------------------------------- |
| `attribution_model_result_id`  | String    | Unique identifier for the result      |
| `touchpoint_occurred_at`       | Timestamp | When the touchpoint occurred          |
| `attribution_model_name`       | String    | Name of the attribution model         |
| `touchpoint_batch_id`          | String    | Touchpoint batch identifier           |
| `touchpoint_event_id`          | String    | Event ID of the touchpoint            |
| `attributed_event_id`          | String    | Event that received attribution       |
| `person_id`                    | String    | Person who received attribution       |
| `attributed_event_occurred_at` | Timestamp | When the attributed event occurred    |
| `fbclid`                       | String    | Facebook click ID that was attributed |

## Attribution Logic

### Last Facebook Click ID Model

The `last_fbclid` model uses a window function approach:

1. **Timeline Creation**: Creates a complete timeline for each person with all
   touchpoint batches
2. **Window Function**: Uses `last_value(fbclid ignore nulls)` to carry forward
   the most recent fbclid for each person
3. **Event Attribution**: Joins with touchpoint paths to attribute the fbclid to
   all events in each batch

**Algorithm:**

```sql
last_value(fbclid ignore nulls) over (
    partition by person_id
    order by touchpoint_occurred_at
    rows between unbounded preceding and current row
) as last_fbclid
```

## Usage Examples

### Enable Last Facebook Click ID Attribution

```yaml
# dbt_project.yml
vars:
  nexus:
    attribution_models:
      last_fbclid:
        enabled: true
```

### Query Attribution Results

```sql
-- Get attribution results for a specific person
select
    attribution_model_name,
    touchpoint_occurred_at,
    attributed_event_id,
    attributed_event_occurred_at,
    fbclid
from {{ ref('last_fbclid') }}
where person_id = 'person_123'
order by touchpoint_occurred_at desc
```

### Analyze Attribution Performance

```sql
-- Analyze attribution performance by fbclid
select
    fbclid,
    count(*) as attributed_events,
    count(distinct person_id) as unique_persons,
    min(touchpoint_occurred_at) as first_attribution,
    max(touchpoint_occurred_at) as last_attribution
from {{ ref('last_fbclid') }}
where fbclid is not null
group by fbclid
order by attributed_events desc
```

### Conversion Attribution

```sql
-- Track conversions attributed to specific fbclids
select
    lf.fbclid,
    lf.person_id,
    lf.attributed_event_id,
    e.event_name,
    e.occurred_at as conversion_time
from {{ ref('last_fbclid') }} lf
join {{ ref('nexus_events') }} e
    on lf.attributed_event_id = e.event_id
where e.event_name in ('purchase', 'signup', 'conversion')
    and lf.fbclid is not null
order by e.occurred_at desc
```

## Testing

The template source includes comprehensive tests:

- **Uniqueness**: Attribution model result IDs are unique
- **Not Null**: Required fields validation
- **Accepted Values**: Attribution model names validation
- **Expression Tests**: ID format validation

Run tests with:

```bash
dbt test --select package:nexus attribution_models
```

## Troubleshooting

### Common Issues

**Models Not Building**

- Ensure `nexus.attribution_models.last_fbclid.enabled: true` in your project
  configuration
- Verify that touchpoint data is available from enabled sources

**Missing Attribution Data**

- Check that Facebook click IDs (fbclid) are being captured in touchpoint data
- Verify that touchpoint sources are enabled and configured

**Attribution Window Issues**

- Ensure attribution window is appropriate for your business model
- Check that touchpoint data covers the required time period

### Debug Queries

```sql
-- Check attribution model data availability
select
    attribution_model_name,
    count(*) as result_count,
    count(distinct person_id) as unique_persons,
    min(touchpoint_occurred_at) as earliest_attribution,
    max(touchpoint_occurred_at) as latest_attribution
from {{ ref('last_fbclid') }}
group by attribution_model_name

-- Check fbclid distribution
select
    case
        when fbclid is null then 'No fbclid'
        else 'Has fbclid'
    end as fbclid_status,
    count(*) as event_count
from {{ ref('last_fbclid') }}
group by 1
```

## Migration from Legacy Attribution

If migrating from a legacy attribution implementation:

1. **Backup Current Implementation**: Save existing attribution models and tests
2. **Enable Template Models**: Set
   `nexus.attribution_models.last_fbclid.enabled: true`
3. **Test Migration**: Run `dbt run --select package:nexus attribution_models`
4. **Update References**: Update any custom models referencing old attribution
   models
5. **Remove Legacy Files**: Delete old attribution model files

## Best Practices

1. **Attribution Windows**: Use appropriate attribution windows for your
   business
2. **Data Quality**: Monitor for missing or invalid touchpoint data
3. **Performance**: Consider incremental processing for large datasets
4. **Testing**: Regularly validate attribution logic with known test cases
5. **Documentation**: Document any custom attribution logic or business rules

## Adding New Attribution Models

To add a new attribution model to the template source:

1. **Create Model File**: Add the model SQL file to `attribution-models/`
2. **Add Configuration**: Update `dbt_project.yml` with model configuration
3. **Add Tests**: Include comprehensive tests in `attribution_models.yml`
4. **Update Documentation**: Add model documentation to this file
5. **Test Integration**: Verify the model works with existing attribution
   infrastructure

## Support

For issues or questions:

- Check the [troubleshooting guide](../../explanations/troubleshooting.md)
- Review existing implementations in other client projects
- Consult the
  [attribution modeling documentation](../../reference/attribution.md)

---

**Ready to get started?** Enable the attribution models in your project
configuration and run `dbt run --select package:nexus attribution_models` to
begin tracking attribution.
