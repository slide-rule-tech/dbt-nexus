---
title: Troubleshooting Attribution Issues
tags: [how-to, attribution, troubleshooting, debugging]
summary:
  Common attribution issues and how to diagnose them, including power user
  analysis, deduplication debugging, and performance troubleshooting.
---

# Troubleshooting Attribution Issues

This guide helps diagnose common issues in the Nexus attribution system, with
real examples and debugging queries.

---

## Common Attribution Issues

### Issue 1: Lower Batch Count Than Expected

**Symptom**: `nexus_touchpoint_path_batches` has significantly fewer rows than
`nexus_touchpoints`

**Expected**: Batch count should be roughly 50-70% of touchpoint count after
deduplication **Actual**: May see batch counts that are 30-40% of touchpoint
count

**Root Cause**: High deduplication rates due to power users or internal users

#### Diagnosis Queries

**Step 1: Check Overall Deduplication Impact**

```sql
-- Compare touchpoint counts through the pipeline
SELECT 'Raw touchpoints' as stage, count(*) as count FROM nexus_touchpoints
UNION ALL
SELECT 'After deduplication' as stage, count(*) as count
FROM nexus_touchpoint_paths
UNION ALL
SELECT 'Final batches' as stage, count(*) as count
FROM nexus_touchpoint_path_batches
ORDER BY count DESC
```

**Step 2: Identify Power Users**

```sql
-- Find people with extreme touchpoint counts
WITH dedup_analysis AS (
  SELECT
    p.person_id,
    count(*) as total_touchpoints,
    count(CASE WHEN duplicate_touchpoint = false THEN 1 END) as touchpoints_kept,
    count(CASE WHEN duplicate_touchpoint = true THEN 1 END) as touchpoints_removed
  FROM (
    SELECT
      t.*,
      p.person_id,
      CASE
        WHEN lag(t.attribution_deduplication_key) OVER (
          PARTITION BY p.person_id
          ORDER BY t.occurred_at
        ) = t.attribution_deduplication_key
        THEN true
        ELSE false
      END as duplicate_touchpoint
    FROM nexus_touchpoints t
    INNER JOIN nexus_person_participants p ON t.touchpoint_event_id = p.event_id
  ) dedup_check
  GROUP BY p.person_id
)
SELECT
  person_id,
  total_touchpoints,
  touchpoints_removed,
  round(touchpoints_removed * 100.0 / total_touchpoints, 2) as percent_removed
FROM dedup_analysis
WHERE total_touchpoints > 1000  -- Focus on power users
ORDER BY total_touchpoints DESC
LIMIT 10
```

**Step 3: Analyze Power User Behavior**

```sql
-- Check if these are internal users
SELECT
  e.event_name,
  count(*) as event_count,
  count(DISTINCT p.person_id) as unique_people
FROM nexus_events e
INNER JOIN nexus_person_participants p ON e.event_id = p.event_id
WHERE p.person_id IN ('per_39d2cd41d42a1e4e35899fa3d6a51a3d') -- Replace with actual power user IDs
GROUP BY e.event_name
ORDER BY event_count DESC
LIMIT 20
```

#### Expected Findings: Power User Patterns

**Internal User Indicators:**

- **Extreme daily usage**: 25-73 events per day for months
- **Admin activities**: Dashboard, my-listings, create-listing, notifications
- **Brand searches**: Google organic with no UTM campaigns
- **Consistent attribution**: Same dedup key (Google organic) for long periods
- **High event variety**: 100-1,500+ unique event types

**Example Power User Profile:**

```
Person ID: per_39d2cd41d42a1e4e35899fa3d6a51a3d
- 12,012 total events over 474 days (25 events/day average)
- 9,887 touchpoints → 45 kept (99.54% deduplication)
- Primary activities: Dashboard (4,806), Homepage (4,014), Admin pages
- Attribution: 100% Google organic referral traffic
- Pattern: Daily user accessing internal features via Google search
```

#### Resolution

**This is typically expected behavior:**

- ✅ **High deduplication rates** (90%+) for internal users are normal
- ✅ **Effective noise filtering** prevents internal usage from skewing
  attribution
- ✅ **Real customer attribution** is preserved while internal activity is
  deduplicated

**Action**: No fix needed - the system is working as designed to filter internal
user noise.

---

## Issue 2: Attribution Rate Lower Than Expected

**Symptom**: Only 60-70% of events receive attribution when expecting 80%+

**Root Cause**: Legitimate unattributed events (direct traffic, pre-touchpoint
events)

#### Diagnosis Queries

**Check Unattributed Event Breakdown**

```sql
-- Analyze why events don't have attribution
WITH unattributed_events AS (
  SELECT e.*
  FROM nexus_events e
  LEFT JOIN nexus_touchpoint_paths tp ON e.event_id = tp.event_id
  WHERE tp.event_id IS NULL
),
person_touchpoint_check AS (
  SELECT
    ue.event_id,
    ue.occurred_at,
    pp.person_id,
    CASE
      WHEN pwt.person_id IS NOT NULL THEN 'Person HAS touchpoints elsewhere'
      ELSE 'Person has NO touchpoints at all'
    END as person_touchpoint_status
  FROM unattributed_events ue
  LEFT JOIN nexus_person_participants pp ON ue.event_id = pp.event_id
  LEFT JOIN (
    SELECT DISTINCT pp.person_id
    FROM nexus_person_participants pp
    INNER JOIN nexus_touchpoints tp ON pp.event_id = tp.touchpoint_event_id
  ) pwt ON pp.person_id = pwt.person_id
)
SELECT
  person_touchpoint_status,
  count(*) as event_count,
  round(count(*) * 100.0 / sum(count(*)) OVER(), 2) as percentage
FROM person_touchpoint_check
WHERE person_id IS NOT NULL
GROUP BY person_touchpoint_status
```

**Expected Results:**

- **~60%**: People with no touchpoints (direct traffic) → **Normal**
- **~30%**: Events before person's first touchpoint → **Normal**
- **~10%**: Other edge cases → **Acceptable**

---

## Issue 3: Performance Problems

**Symptom**: Attribution models taking too long to run or timing out

#### Common Causes and Solutions

**1. Cartesian Product Explosion**

```sql
-- BAD: Creates massive row explosion
FROM touchpoints t
INNER JOIN events e ON t.person_id = e.person_id
WHERE t.occurred_at < e.event_occurred_at
```

**Solution**: Use MAX aggregation strategy (implemented in
`nexus_touchpoint_paths`)

```sql
-- GOOD: Find latest touchpoint first, then join
WITH latest_touchpoint_times AS (
  SELECT event_id, MAX(touchpoint_occurred_at) as latest_touchpoint_at
  FROM events e
  INNER JOIN touchpoints t ON e.person_id = t.person_id
    AND t.occurred_at < e.event_occurred_at
    AND datediff('day', t.occurred_at, e.event_occurred_at) <= 90
  GROUP BY event_id
)
```

**2. Missing Attribution Window**

- **Problem**: No time limit on touchpoint attribution
- **Solution**: Add 90-day attribution window to prevent runaway joins

**3. No Materialization Strategy**

- **Problem**: Models running as views instead of tables
- **Solution**: Use `materialized='table'` for attribution models

---

## Issue 4: Duplicate Attribution Results

**Symptom**: Events getting multiple touchpoints when expecting 1:1 relationship

#### Diagnosis

**Check for Timestamp Ties**

```sql
-- Find events with multiple touchpoints at same timestamp
SELECT
  event_id,
  count(*) as touchpoint_count
FROM nexus_touchpoint_paths
GROUP BY event_id
HAVING count(*) > 1
LIMIT 10
```

**Solution**: Tie-breaker logic (implemented in `nexus_touchpoint_paths`)

```sql
-- Add deterministic tie-breaker
ROW_NUMBER() OVER (
  PARTITION BY event_id
  ORDER BY touchpoint_id  -- Deterministic ordering
) as tie_breaker_rank
```

---

## Debugging Attribution Deduplication

### Understanding High Deduplication Rates

**Normal Deduplication Scenarios:**

- **Page refreshes**: Same page, same attribution, within seconds
- **Session continuation**: Same campaign context across page views
- **Internal users**: Employees/power users with consistent Google organic
  traffic

**Problematic Deduplication Scenarios:**

- **Different campaigns** getting same dedup key
- **Cross-session deduplication** when sessions should be separate
- **Time-based issues** where old touchpoints affect new ones

### Deduplication Analysis Queries

**Check Dedup Key Distribution**

```sql
-- Understand what's being deduplicated
SELECT
  t.channel,
  t.touchpoint_type,
  t.referrer,
  count(*) as touchpoint_count,
  count(DISTINCT t.touchpoint_id) as unique_touchpoints,
  count(DISTINCT p.person_id) as unique_people,
  round(count(*) / count(DISTINCT p.person_id), 2) as avg_touchpoints_per_person
FROM nexus_touchpoints t
INNER JOIN nexus_person_participants p ON t.touchpoint_event_id = p.event_id
WHERE t.attribution_deduplication_key = 'att_dedup_3612d05614d4825cab013879906fe684'  -- Replace with problematic key
GROUP BY t.channel, t.touchpoint_type, t.referrer
ORDER BY touchpoint_count DESC
```

**Analyze Power User Patterns**

```sql
-- Check if high deduplication users are internal
SELECT
  p.person_id,
  count(DISTINCT e.event_id) as total_events,
  count(DISTINCT date(e.occurred_at)) as unique_days_active,
  datediff('day', min(e.occurred_at), max(e.occurred_at)) as total_days_span,
  count(DISTINCT e.event_id) / datediff('day', min(e.occurred_at), max(e.occurred_at)) as avg_events_per_day,
  count(DISTINCT e.event_name) as unique_event_types
FROM nexus_events e
INNER JOIN nexus_person_participants p ON e.event_id = p.event_id
WHERE p.person_id = 'per_39d2cd41d42a1e4e35899fa3d6a51a3d'  -- Replace with power user ID
GROUP BY p.person_id
```

### Power User Identification

**Internal User Red Flags:**

- **>20 events per day** consistently
- **>200 unique days active** over long periods
- **Admin page access**: `/dashboard`, `/my-listings`, `/create-listing`
- **Brand searches**: Google organic with no UTM campaigns
- **>100 unique event types** (exploring all features)

**Legitimate Power User vs Internal User:**

- **Legitimate**: High activity but focused on core user flows (search, book,
  manage)
- **Internal**: High activity across admin features, testing flows, unusual page
  access

---

## Performance Optimization Checklist

### Model Configuration

- ✅ Use `materialized='table'` for all attribution models
- ✅ Add appropriate `tags` for organization
- ✅ Include 90-day attribution window
- ✅ Use MAX aggregation strategy to avoid cartesian products

### Query Optimization

- ✅ Partition window functions by `person_id`
- ✅ Order by `occurred_at` for temporal logic
- ✅ Use deterministic tie-breakers for duplicate timestamps
- ✅ Include proper indexes on `person_id`, `event_id`, `touchpoint_id`

### Data Quality Validation

- ✅ Validate 1:1 event-to-touchpoint relationship
- ✅ Check attribution coverage rates (expect 60-75%)
- ✅ Monitor deduplication rates (expect 40-60% for normal users)
- ✅ Identify and analyze power users separately

---

## Expected Attribution Metrics

### Healthy Attribution System

- **Attribution Coverage**: 60-75% of events
- **Deduplication Rate**: 40-60% overall (higher for power users)
- **Batch Compression**: 5-7:1 ratio (events to batches)
- **Processing Time**: <2 minutes for 10M+ events

### Red Flags

- **<50% attribution coverage**: Missing touchpoint sources
- **>80% deduplication rate** across all users: Dedup key too broad
- **>15x row explosion**: Missing attribution window or cartesian product
- **>10 minute processing**: Performance optimization needed

---

## Real-World Example: Power User Analysis

**Case Study: `per_39d2cd41d42a1e4e35899fa3d6a51a3d`**

**Profile:**

- **12,012 events** over 474 days (25 events/day)
- **9,887 touchpoints** → **45 kept** (99.54% deduplication)
- **315 unique days active** over 15+ months
- **91 unique event types**

**Touchpoint Patterns:**

- **4,014 homepage visits** from Google organic
- **2,854 dashboard visits** over 288 unique days
- **1,278 admin requests** (`/requests/wyndham`)
- **432 listing creation activities**

**Attribution Analysis:**

- **100% Google organic referral** traffic
- **No UTM campaigns** (direct brand searches)
- **Consistent daily usage** of internal features
- **Admin-level access** patterns

**Conclusion**: Clear internal user or super power user. High deduplication rate
(99.54%) is **expected and correct** - prevents internal usage from skewing
customer attribution data.

**Action**: No fix needed. Consider filtering these users from marketing
attribution reports if desired, but the deduplication is working correctly.

---

## Debugging Workflow

### 1. Check Pipeline Health

```sql
-- Get overall attribution pipeline metrics
SELECT
  'nexus_events' as table_name, count(*) as row_count FROM nexus_events
UNION ALL
SELECT 'nexus_touchpoints' as table_name, count(*) as row_count FROM nexus_touchpoints
UNION ALL
SELECT 'nexus_touchpoint_paths' as table_name, count(*) as row_count FROM nexus_touchpoint_paths
UNION ALL
SELECT 'nexus_touchpoint_path_batches' as table_name, count(*) as row_count FROM nexus_touchpoint_path_batches
ORDER BY row_count DESC
```

### 2. Analyze Deduplication Impact

```sql
-- Check deduplication effectiveness
SELECT
  attribution_deduplication_key,
  count(*) as total_touchpoints,
  count(DISTINCT person_id) as unique_people,
  avg_touchpoints_per_person = count(*) / count(DISTINCT person_id)
FROM nexus_touchpoints t
INNER JOIN nexus_person_participants p ON t.touchpoint_event_id = p.event_id
GROUP BY attribution_deduplication_key
HAVING count(*) > 10000  -- Focus on high-volume dedup keys
ORDER BY total_touchpoints DESC
```

### 3. Identify Power Users

```sql
-- Find users with suspicious activity levels
SELECT
  person_id,
  count(DISTINCT event_id) as total_events,
  count(DISTINCT date(occurred_at)) as unique_days_active,
  count(DISTINCT event_id) / count(DISTINCT date(occurred_at)) as avg_events_per_day
FROM nexus_events e
INNER JOIN nexus_person_participants p ON e.event_id = p.event_id
GROUP BY person_id
HAVING count(DISTINCT event_id) / count(DISTINCT date(occurred_at)) > 20  -- >20 events/day
ORDER BY total_events DESC
```

### 4. Validate Attribution Logic

```sql
-- Ensure 1:1 event-to-touchpoint relationship
SELECT
  CASE
    WHEN count(DISTINCT event_id) = count(*) THEN '✅ Perfect 1:1 relationship'
    ELSE '❌ Multiple touchpoints per event detected'
  END as validation_result,
  count(*) as total_attribution_records,
  count(DISTINCT event_id) as unique_events
FROM nexus_touchpoint_paths
```

---

## When to Investigate vs Accept

### Investigate Further

- **Attribution coverage <50%**: Likely missing touchpoint sources
- **Processing time >10 minutes**: Performance optimization needed
- **Row explosion >20x**: Cartesian product or missing attribution window
- **Zero deduplication**: Dedup key not working

### Accept as Normal

- **Attribution coverage 60-75%**: Typical for web analytics
- **High deduplication for power users** (80%+): Expected for internal users
- **Batch compression 5-7:1**: Efficient batching working correctly
- **Processing time <5 minutes**: Good performance for large datasets

---

## Performance Monitoring

### Key Metrics to Track

- **Attribution coverage rate**: Target 60-75%
- **Deduplication rate**: Target 40-60% overall
- **Batch compression ratio**: Target 5-7:1
- **Processing time**: Target <5 minutes for 10M events
- **Power user identification**: Monitor users with >1000 touchpoints

### Health Check Query

```sql
-- Comprehensive attribution health check
SELECT
  'Attribution Coverage' as metric,
  round(
    count(DISTINCT tp.event_id) * 100.0 /
    count(DISTINCT e.event_id), 2
  ) as percentage
FROM nexus_events e
LEFT JOIN nexus_touchpoint_paths tp ON e.event_id = tp.event_id

UNION ALL

SELECT
  'Deduplication Rate' as metric,
  round(
    (count(DISTINCT t.touchpoint_id) - count(DISTINCT tp.last_touchpoint_id)) * 100.0 /
    count(DISTINCT t.touchpoint_id), 2
  ) as percentage
FROM nexus_touchpoints t
LEFT JOIN nexus_touchpoint_paths tp ON t.touchpoint_id = tp.last_touchpoint_id

UNION ALL

SELECT
  'Batch Compression Ratio' as metric,
  round(
    count(DISTINCT tp.touchpoint_path_id) * 1.0 /
    count(DISTINCT tb.touchpoint_batch_id), 2
  ) as ratio
FROM nexus_touchpoint_paths tp
LEFT JOIN nexus_touchpoint_path_batches tb ON tp.touchpoint_batch_id = tb.touchpoint_batch_id
```

The Nexus attribution system is designed to handle these scenarios gracefully
while maintaining data quality and performance.
