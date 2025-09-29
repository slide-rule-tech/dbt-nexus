---
title: Last Facebook Click ID Attribution Model
tags: [attribution, fbclid, facebook, last-click, window-functions]
summary:
  Window function-based attribution model that carries forward the most recent
  Facebook click ID for each person across their touchpoint journey
---

# Last Facebook Click ID Attribution Model

The `last_fbclid` attribution model tracks the most recent Facebook click ID
(fbclid) for each person across their touchpoint journey. This model uses a
window function approach to carry forward the last non-null fbclid for each
person, assigning it to all subsequent events until a new fbclid is encountered.

## How It Works

### 1. Touchpoint Timeline Creation

The model creates a complete timeline for each person with all touchpoint
batches, ordered by occurrence time.

### 2. Window Function Attribution

Uses `last_value(fbclid ignore nulls)` to carry forward the most recent fbclid
for each person across their journey:

```sql
last_value(fbclid ignore nulls) over (
    partition by person_id
    order by touchpoint_occurred_at
    rows between unbounded preceding and current row
) as last_fbclid
```

### 3. Event Attribution

Joins with touchpoint paths to attribute the fbclid to all events in each batch,
creating attribution results.

## Use Cases

### Facebook Ad Attribution

Track which Facebook ads are driving conversions by following the fbclid through
the customer journey.

### Cross-Session Attribution

Maintain attribution across multiple sessions, ensuring Facebook clicks are
properly credited even if the user returns later.

### Social Media Campaign Tracking

Measure the effectiveness of Facebook campaigns by tracking the complete
attribution path.

## Configuration

### Basic Configuration

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

The `last_fbclid` model outputs the following fields:

| Field                          | Type      | Description                           |
| ------------------------------ | --------- | ------------------------------------- |
| `attribution_model_result_id`  | String    | Unique identifier for the result      |
| `touchpoint_occurred_at`       | Timestamp | When the touchpoint occurred          |
| `attribution_model_name`       | String    | Always "last_fbclid"                  |
| `touchpoint_batch_id`          | String    | Touchpoint batch identifier           |
| `touchpoint_event_id`          | String    | Event ID of the touchpoint            |
| `attributed_event_id`          | String    | Event that received attribution       |
| `person_id`                    | String    | Person who received attribution       |
| `attributed_event_occurred_at` | Timestamp | When the attributed event occurred    |
| `fbclid`                       | String    | Facebook click ID that was attributed |

## Attribution Logic Details

### Window Function Approach

The model uses a sophisticated window function that:

1. **Partitions by Person**: Each person's journey is processed independently
2. **Orders by Time**: Touchpoints are ordered by occurrence time
3. **Carries Forward Values**: The last non-null fbclid is carried forward
4. **Handles Nulls**: Ignores null fbclid values in the calculation

### Touchpoint Batching

Events are processed in batches to improve performance:

- Multiple events can share the same touchpoint batch
- Attribution is calculated at the batch level
- Results are then joined with individual events

### Attribution Window

The model respects a 90-day attribution window by default, meaning:

- Touchpoints older than 90 days are not considered
- This prevents stale attribution from very old touchpoints
- The window can be configured via `attribution_window_days`

## Usage Examples

### Query Attribution Results

```sql
-- Get fbclid attribution for a specific person
select
    touchpoint_occurred_at,
    attributed_event_id,
    attributed_event_occurred_at,
    fbclid
from {{ ref('last_fbclid') }}
where person_id = 'person_123'
order by touchpoint_occurred_at desc
```

### Analyze Facebook Campaign Performance

```sql
-- Analyze Facebook campaign performance by fbclid
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

### Track Conversion Attribution

```sql
-- Track conversions attributed to Facebook clicks
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

### Attribution Journey Analysis

```sql
-- Analyze the complete attribution journey for a person
with person_journey as (
    select
        person_id,
        touchpoint_occurred_at,
        fbclid,
        attributed_event_id,
        attributed_event_occurred_at,
        row_number() over (
            partition by person_id
            order by touchpoint_occurred_at
        ) as journey_step
    from {{ ref('last_fbclid') }}
    where person_id = 'person_123'
)
select
    journey_step,
    touchpoint_occurred_at,
    fbclid,
    attributed_event_id,
    attributed_event_occurred_at
from person_journey
order by journey_step
```

## Performance Considerations

### Window Function Optimization

The model uses window functions which can be resource-intensive on large
datasets:

- Consider partitioning by person_id for better performance
- Monitor query execution times on large datasets
- Use appropriate indexing on touchpoint_occurred_at

### Batch Processing

Touchpoint batching helps improve performance:

- Reduces the number of window function calculations
- Groups related events together
- Minimizes memory usage

## Testing

### Model Tests

The model includes comprehensive tests:

- **Uniqueness**: Attribution model result IDs are unique
- **Not Null**: Required fields validation
- **Accepted Values**: Attribution model name validation
- **Expression Tests**: ID format validation

### Data Quality Checks

```sql
-- Check for missing fbclid data
select
    case
        when fbclid is null then 'No fbclid'
        else 'Has fbclid'
    end as fbclid_status,
    count(*) as event_count
from {{ ref('last_fbclid') }}
group by 1

-- Check attribution distribution
select
    attribution_model_name,
    count(*) as result_count,
    count(distinct person_id) as unique_persons
from {{ ref('last_fbclid') }}
group by attribution_model_name
```

## Troubleshooting

### Common Issues

**No Attribution Results**

- Check that Facebook click IDs (fbclid) are being captured in touchpoint data
- Verify that touchpoint sources are enabled and configured
- Ensure person resolution is working correctly

**Missing fbclid Values**

- Verify that Facebook tracking is properly implemented
- Check that fbclid parameters are being passed in URLs
- Review touchpoint data for fbclid presence

**Performance Issues**

- Monitor window function performance on large datasets
- Consider adding indexes on person_id and touchpoint_occurred_at
- Review touchpoint batching configuration

### Debug Queries

```sql
-- Check fbclid data availability in touchpoints
select
    source,
    count(*) as total_touchpoints,
    count(fbclid) as touchpoints_with_fbclid,
    count(fbclid) / count(*) * 100 as fbclid_percentage
from {{ ref('nexus_touchpoints') }}
group by source

-- Check attribution model results
select
    count(*) as total_results,
    count(fbclid) as results_with_fbclid,
    min(touchpoint_occurred_at) as earliest_attribution,
    max(touchpoint_occurred_at) as latest_attribution
from {{ ref('last_fbclid') }}
```

## Best Practices

1. **Monitor Data Quality**: Regularly check for missing fbclid values
2. **Validate Attribution Logic**: Test with known attribution scenarios
3. **Consider Attribution Windows**: Use appropriate time windows for your
   business model
4. **Document Custom Logic**: If modifying the model, document changes clearly
5. **Performance Monitoring**: Monitor query performance on large datasets

## Related Documentation

- [Attribution Models Overview](../index.md) - General attribution concepts
- [Touchpoint Tracking](../touchpoints.md) - How touchpoints are collected
- [Identity Resolution](../../explanations/identity-resolution.md) - Person
  resolution process
- [Facebook Attribution Setup](../../how-to/facebook-attribution-setup.md) -
  Setting up Facebook tracking

---

**Ready to use this model?** Enable it in your project configuration and run
`dbt run --select package:nexus last_fbclid` to begin tracking Facebook
attribution.
