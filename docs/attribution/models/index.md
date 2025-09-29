---
title: Attribution Models
tags: [attribution, models, configuration, touchpoints]
summary:
  Pre-built attribution models for tracking how different touchpoints contribute
  to conversions and events
---

# Attribution Models

The dbt-nexus package includes pre-built attribution models that help you
understand which marketing touchpoints are most effective at driving
conversions. These models use advanced window functions and touchpoint tracking
to provide accurate attribution analysis.

## Overview

Attribution models answer the question: "Which touchpoint should get credit for
this conversion?" The nexus package provides several pre-built models that can
be enabled and configured based on your attribution needs.

## Available Models

### Last Facebook Click ID (`last_fbclid`)

Tracks the most recent Facebook click ID (fbclid) for each person across their
touchpoint journey. This model carries forward the last non-null fbclid for each
person, assigning it to all subsequent events until a new fbclid is encountered.

**Best for:**

- Sending conversions to Facebook CAPI

## How Attribution Models Work

### 1. Touchpoint Collection

Attribution models start with touchpoint data from enabled sources. Touchpoints
are events that contain attribution information like UTM parameters, click IDs,
or referrer data.

### 2. Person Journey Mapping

Each person's touchpoint journey is mapped using their resolved person ID,
creating a timeline of all attribution-relevant events.

### 3. Attribution Logic Application

The specific attribution model logic is applied to determine which touchpoint
should receive credit for each conversion event.

### 4. Result Generation

Attribution results are generated with metadata about which touchpoint was
attributed to which event, when it occurred, and the attribution model used.

## Configuration

### Enable Attribution Models

Add attribution models to your `dbt_project.yml`:

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

## Attribution Model Schema

All attribution models follow a consistent schema:

| Field                          | Type      | Description                        |
| ------------------------------ | --------- | ---------------------------------- |
| `attribution_model_result_id`  | String    | Unique identifier for the result   |
| `touchpoint_occurred_at`       | Timestamp | When the touchpoint occurred       |
| `attribution_model_name`       | String    | Name of the attribution model      |
| `touchpoint_batch_id`          | String    | Touchpoint batch identifier        |
| `touchpoint_event_id`          | String    | Event ID of the touchpoint         |
| `attributed_event_id`          | String    | Event that received attribution    |
| `person_id`                    | String    | Person who received attribution    |
| `attributed_event_occurred_at` | Timestamp | When the attributed event occurred |

## Usage Examples

### Query Attribution Results

```sql
-- Get attribution results for a specific person
select
    attribution_model_name,
    touchpoint_occurred_at,
    attributed_event_id,
    attributed_event_occurred_at
from {{ ref('nexus_attribution_model_results') }}
where person_id = 'person_123'
order by touchpoint_occurred_at desc
```

### Analyze Attribution Performance

```sql
-- Analyze attribution performance by model
select
    attribution_model_name,
    count(*) as attributed_events,
    count(distinct person_id) as unique_persons,
    min(touchpoint_occurred_at) as first_attribution,
    max(touchpoint_occurred_at) as last_attribution
from {{ ref('nexus_attribution_model_results') }}
group by attribution_model_name
order by attributed_events desc
```

### Track Conversions

```sql
-- Track conversions attributed to specific models
select
    amr.attribution_model_name,
    amr.person_id,
    amr.attributed_event_id,
    e.event_name,
    e.occurred_at as conversion_time
from {{ ref('nexus_attribution_model_results') }} amr
join {{ ref('nexus_events') }} e
    on amr.attributed_event_id = e.event_id
where e.event_name in ('purchase', 'signup', 'conversion')
order by e.occurred_at desc
```

## Prerequisites

Before using attribution models, ensure you have:

1. **Enabled Touchpoint Sources**: Sources with `attribution: true` in your
   configuration
2. **Person Resolution**: Working person identity resolution
3. **Touchpoint Data**: UTM parameters, click IDs, or referrer data in your
   events

## Testing

Run attribution model tests:

```bash
dbt test --select package:nexus attribution_models
```

## Troubleshooting

### Common Issues

**No Attribution Data**

- Check that touchpoint sources are enabled and configured
- Verify that attribution data (UTM parameters, click IDs) is being captured
- Ensure person resolution is working correctly

**Models Not Building**

- Verify attribution models are enabled in your configuration
- Check that required touchpoint data is available
- Review error logs for specific issues

### Debug Queries

```sql
-- Check attribution model data availability
select
    attribution_model_name,
    count(*) as result_count,
    count(distinct person_id) as unique_persons,
    min(touchpoint_occurred_at) as earliest_attribution,
    max(touchpoint_occurred_at) as latest_attribution
from {{ ref('nexus_attribution_model_results') }}
group by attribution_model_name

-- Check touchpoint data availability
select
    source,
    count(*) as touchpoint_count,
    count(distinct person_id) as unique_persons
from {{ ref('nexus_touchpoints') }}
group by source
```

## Best Practices

1. **Choose Appropriate Models**: Select attribution models that match your
   business model and marketing channels
2. **Monitor Data Quality**: Regularly check for missing or invalid touchpoint
   data
3. **Test Attribution Logic**: Validate attribution results with known test
   cases
4. **Consider Attribution Windows**: Use appropriate time windows for your
   business model
5. **Document Custom Logic**: If you create custom attribution models, document
   the business logic clearly

## Adding New Attribution Models

To add a new attribution model:

1. **Create Model File**: Add the model SQL file to `attribution-models/`
2. **Add Configuration**: Update `dbt_project.yml` with model configuration
3. **Add Tests**: Include comprehensive tests in the model's YAML file
4. **Update Documentation**: Add model documentation
5. **Test Integration**: Verify the model works with existing infrastructure

## Related Documentation

- [Template Sources](../template-sources/index.md) - Configure data sources
- [Touchpoint Tracking](touchpoints.md) - How touchpoints are collected
- [Identity Resolution](../explanations/identity-resolution.md) - Person
  resolution process
- [Attribution Framework](../explanations/attribution.md) - Attribution concepts

---

**Ready to get started?** Enable attribution models in your project
configuration and run `dbt run --select package:nexus attribution_models` to
begin tracking attribution.
