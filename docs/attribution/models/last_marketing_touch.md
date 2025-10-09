---
title: Last Marketing Touch Attribution Model
tags: [attribution, models, last-touch, marketing]
summary:
  Attribution model that tracks the most recent web/marketing touchpoint for
  each event, providing simple last-touch attribution focused on marketing
  channels.
---

# Last Marketing Touch Attribution Model

The `last_marketing_touch` model implements a straightforward last-touch
attribution strategy focused specifically on web and marketing touchpoints. It
attributes each event to the most recent marketing touchpoint that preceded it.

---

## Overview

This model answers the question: **"Which marketing touchpoint was most recently
responsible for this event?"**

Unlike general last-touch attribution that might include any type of touchpoint,
`last_marketing_touch` specifically filters for `touchpoint_type = 'web'`,
making it ideal for understanding digital marketing performance.

---

## How It Works

### 1. Touchpoint Filtering

The model starts with `nexus_touchpoint_path_batches` and filters for web
marketing touchpoints only:

```sql
where touchpoint_type = 'web'
```

This ensures only marketing-related touchpoints (paid search, organic, display
ads, email campaigns, etc.) are included in attribution.

### 2. Event Attribution

Each event is attributed to the most recent web touchpoint that preceded it
within the 90-day attribution window. The attribution is applied at the batch
level for efficiency - all events in a touchpoint batch receive the same
attribution.

### 3. Attribution Fields

The model provides comprehensive marketing attribution data:

- `source` - Traffic source (e.g., 'google', 'facebook', 'email')
- `medium` - Marketing medium (e.g., 'cpc', 'organic', 'email', 'display')
- `campaign` - Campaign name
- `content` - Ad content or variant
- `gclid` - Google Click ID for Google Ads tracking

---

## Configuration

### Enable the Model

Add to your `dbt_project.yml`:

```yaml
vars:
  nexus:
    attribution_models:
      last_marketing_touch:
        enabled: true
```

### Model is Enabled by Default

The `last_marketing_touch` model is enabled by default. To disable it:

```yaml
vars:
  nexus:
    attribution_models:
      last_marketing_touch:
        enabled: false
```

---

## Output Schema

The model produces the standard attribution model schema:

| Column                         | Type      | Description                            |
| ------------------------------ | --------- | -------------------------------------- |
| `attribution_model_result_id`  | String    | Unique identifier (attr*res*\*)        |
| `touchpoint_occurred_at`       | Timestamp | When the marketing touchpoint occurred |
| `attribution_model_name`       | String    | Always 'last_marketing_touch'          |
| `touchpoint_batch_id`          | String    | Batch identifier                       |
| `touchpoint_event_id`          | String    | Event ID of the touchpoint             |
| `attributed_event_id`          | String    | Event receiving attribution            |
| `person_id`                    | String    | Person identifier                      |
| `attributed_event_occurred_at` | Timestamp | When the attributed event occurred     |
| `source`                       | String    | Marketing source                       |
| `medium`                       | String    | Marketing medium                       |
| `campaign`                     | String    | Campaign name                          |
| `content`                      | String    | Ad content                             |
| `gclid`                        | String    | Google Click ID                        |

---

## Usage Examples

### Basic Attribution Analysis

```sql
-- See which marketing sources drive the most events
select
    source,
    medium,
    count(*) as attributed_events,
    count(distinct person_id) as unique_persons
from {{ ref('last_marketing_touch') }}
group by source, medium
order by attributed_events desc
```

### Conversion Attribution

```sql
-- Attribute conversions to marketing touchpoints
select
    lmt.source,
    lmt.medium,
    lmt.campaign,
    count(*) as conversions,
    sum(e.value) as total_value
from {{ ref('last_marketing_touch') }} lmt
inner join {{ ref('nexus_events') }} e
    on lmt.attributed_event_id = e.event_id
where e.event_name in ('purchase', 'signup', 'conversion')
group by lmt.source, lmt.medium, lmt.campaign
order by total_value desc
```

### Time-to-Conversion Analysis

```sql
-- Analyze how long between touchpoint and conversion
select
    source,
    medium,
    avg(datediff(day, touchpoint_occurred_at, attributed_event_occurred_at)) as avg_days_to_convert,
    median(datediff(day, touchpoint_occurred_at, attributed_event_occurred_at)) as median_days_to_convert
from {{ ref('last_marketing_touch') }}
group by source, medium
order by avg_days_to_convert
```

### Campaign Performance

```sql
-- Campaign-level attribution with conversion metrics
select
    source,
    medium,
    campaign,
    count(distinct attributed_event_id) as total_attributions,
    count(distinct person_id) as unique_persons,
    count(distinct touchpoint_batch_id) as unique_touchpoints,
    min(touchpoint_occurred_at) as campaign_start,
    max(touchpoint_occurred_at) as campaign_end
from {{ ref('last_marketing_touch') }}
group by source, medium, campaign
order by total_attributions desc
```

---

## When to Use This Model

### Best For:

- **Digital marketing analysis** - Understanding which marketing channels drive
  conversions
- **Campaign optimization** - Identifying best-performing campaigns
- **Channel attribution** - Comparing paid vs organic vs email performance
- **Quick insights** - Simple last-touch logic that's easy to understand and
  explain

### Consider Alternatives When:

- **Long sales cycles** - Consider first-touch or multi-touch models
- **Multiple touchpoints matter** - Use multi-touch attribution models
- **Non-marketing events** - Use general last-touch attribution that includes
  all touchpoint types
- **Complex customer journeys** - Consider position-based or time-decay models

---

## Comparison with Other Models

### vs. Last Touch (General)

| Aspect            | Last Marketing Touch           | Last Touch (General) |
| ----------------- | ------------------------------ | -------------------- |
| Touchpoint Filter | `touchpoint_type = 'web'` only | All touchpoint types |
| Focus             | Digital marketing              | All touchpoints      |
| Use Case          | Marketing performance          | Complete attribution |

### vs. First Touch

| Aspect            | Last Marketing Touch    | First Touch              |
| ----------------- | ----------------------- | ------------------------ |
| Attribution Logic | Most recent touchpoint  | First touchpoint ever    |
| Credit Goes To    | Latest marketing effort | Initial awareness driver |
| Use Case          | Conversion optimization | Top-of-funnel analysis   |

### vs. Multi-Touch

| Aspect              | Last Marketing Touch    | Multi-Touch                 |
| ------------------- | ----------------------- | --------------------------- |
| Credit Distribution | 100% to last touchpoint | Distributed across multiple |
| Complexity          | Simple                  | Complex                     |
| Computation         | Fast                    | Slower                      |

---

## Performance Considerations

### Efficiency

The model uses `nexus_touchpoint_path_batches` for efficient processing:

- Events sharing the same last touchpoint are batched together
- Attribution is computed once per batch, not per event
- Typical compression ratio: 5-6 events per batch
- Sub-minute execution times for millions of events

### Data Volume

Expected output sizes:

- **Attribution coverage**: 40-70% of events typically receive web attribution
- **Row count**: Roughly equal to number of events with web touchpoints
- **Batch compression**: 5:1 to 6:1 ratio (batches to individual attributions)

---

## Troubleshooting

### No Attribution Results

**Issue**: Model runs but returns no results

**Solutions**:

1. Verify `nexus_touchpoints` contains records with `touchpoint_type = 'web'`
2. Check that touchpoint sources are configured with `attribution: true`
3. Ensure person resolution is working (check `nexus_person_participants`)
4. Verify events have person IDs

### Low Attribution Coverage

**Issue**: Fewer attributions than expected

**Possible Causes**:

1. **Missing UTM parameters** - Events don't have marketing attribution data
2. **Touchpoint filtering** - Attribution data cleaned to NULL (check data
   quality)
3. **Person resolution gaps** - Events not linked to persons
4. **Attribution window** - Touchpoints older than 90 days are excluded

### Duplicate Attributions

**Issue**: Same event attributed multiple times

**This is expected** - An event can have multiple attribution records if:

- Multiple attribution models are running
- Event appears in multiple person journeys (rare, indicates identity resolution
  issue)

To deduplicate:

```sql
select distinct attributed_event_id, ...
from {{ ref('last_marketing_touch') }}
```

---

## Best Practices

### 1. Clean Attribution Data

Ensure touchpoint data is cleaned before attribution:

- Remove placeholder values (`'(not set)'`, `'null'`)
- Normalize source names (`'google.com'` → `'google'`)
- Filter out non-marketing touchpoints

### 2. Monitor Attribution Coverage

Track the percentage of events with attribution:

```sql
with event_counts as (
    select
        count(*) as total_events,
        count(distinct lmt.attributed_event_id) as attributed_events
    from {{ ref('nexus_events') }} e
    left join {{ ref('last_marketing_touch') }} lmt
        on e.event_id = lmt.attributed_event_id
)
select
    total_events,
    attributed_events,
    round(100.0 * attributed_events / total_events, 2) as attribution_coverage_pct
from event_counts
```

### 3. Analyze Time-to-Conversion

Understanding conversion delays helps optimize campaigns:

```sql
select
    source,
    medium,
    count(*) as conversions,
    avg(datediff(hour, touchpoint_occurred_at, attributed_event_occurred_at)) as avg_hours_to_convert
from {{ ref('last_marketing_touch') }}
group by source, medium
order by conversions desc
```

### 4. Compare with Other Models

Don't rely solely on last-touch attribution:

```sql
-- Compare last touch vs first touch
select
    coalesce(lt.source, ft.source) as source,
    count(distinct lt.attributed_event_id) as last_touch_conversions,
    count(distinct ft.attributed_event_id) as first_touch_conversions
from {{ ref('last_marketing_touch') }} lt
full outer join {{ ref('first_touch_attribution') }} ft
    on lt.attributed_event_id = ft.attributed_event_id
group by source
```

---

## Related Documentation

- [Attribution Framework](../index.md) - Core attribution concepts
- [Attribution Models Overview](index.md) - All available models
- [Touchpoints](../touchpoints.md) - How touchpoints are created
- [Data Quality](../index.md#data-quality-and-cleaning-best-practices) -
  Cleaning best practices

---

**Ready to use?** The model builds automatically when enabled. Query
`{{ ref('last_marketing_touch') }}` to access attribution results, or use the
unified `{{ ref('nexus_attribution_model_results') }}` table to compare across
all attribution models.
