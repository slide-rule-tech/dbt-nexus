---
title: [Model Name] Reference
tags: [reference, models, [category]]
summary: [One-line description of what this model does]
---

# [Model Name] Reference

[Brief description of the model's purpose and role in the system]

## Overview

[What this model does, when to use it, and how it fits into the data flow]

## Schema

| Column        | Type | Description                 | Required | Notes             |
| ------------- | ---- | --------------------------- | -------- | ----------------- |
| `column_name` | type | What this column represents | ✅/❌    | Any special notes |

## Dependencies

### Upstream Models

- `model_name` - Description of what data this provides

### Downstream Models

- `model_name` - How this model is used downstream

## Configuration

```yaml
# dbt_project.yml example
models:
  nexus:
    [category]:
      [model_name]:
        materialized: [table/view/incremental]
        # Other configs
```

## Usage Examples

### Basic Query

```sql
SELECT
    column1,
    column2
FROM {{ ref('[model_name]') }}
WHERE condition
```

### Common Patterns

```sql
-- Example of a typical use case
```

## Performance Notes

- **Indexes**: Recommended indexes for optimal performance
- **Partitioning**: Partitioning strategy if applicable
- **Size**: Typical row counts and growth patterns

## Troubleshooting

### Common Issues

- **Issue**: Description and solution
- **Issue**: Description and solution

### Debugging Queries

```sql
-- Query to debug common problems
```

## Related Documentation

- [Related Model](../path/to/related.md)
- [Related Concept](../../explanations/concept.md)
- [How-to Guide](../../how-to/related-task.md)
