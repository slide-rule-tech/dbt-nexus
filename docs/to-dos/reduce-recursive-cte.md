---
title: Reduce Recursive CTE Performance Issues
tags: [todo, performance, identity-resolution, optimization]
summary:
  Implement linear-scaling algorithms to replace the current recursive CTE
  approach in identity resolution that causes memory errors with large datasets.
---

# Reduce Recursive CTE Performance Issues

## Problem Statement

The current identity resolution implementation uses a recursive CTE that has
**O(n²) to O(n³)** complexity, causing:

- **Memory exhaustion** with large datasets (42M+ identifiers)
- **Exponential intermediate result growth** during recursive expansion
- **Poor scalability** as data volume increases

## Current Implementation Issues

The recursive CTE in `nexus_resolved_person_identifiers.sql`:

1. Starts with every identifier as a potential root (42M starting points)
2. Recursively joins to find connected identifiers through edges
3. Creates cartesian product-like explosion in intermediate results
4. Limited to 2 recursion levels but still causes memory issues

## Proposed Solutions

### 1. Union-Find Algorithm (Priority: High)

- **Complexity**: O(n log n) with path compression
- **Approach**: Iterative graph traversal instead of recursive
- **Benefits**: Near-linear scaling, deterministic memory usage

### 2. Hash-Based Clustering (Priority: High)

- **Complexity**: O(n) - truly linear
- **Approach**: Pre-compute identifier signatures for grouping
- **Benefits**: Fastest for exact matches, easily parallelizable

### 3. Incremental Processing (Priority: Medium)

- **Complexity**: O(Δn) where Δn = new records only
- **Approach**: Only process new/changed identifiers
- **Benefits**: Daily runs process thousands vs millions of records

### 4. Approximate Clustering (Priority: Low)

- **Complexity**: O(n) but approximate results
- **Approach**: Locality Sensitive Hashing for fuzzy matching
- **Benefits**: Linear scaling for fuzzy name/address matching

## Implementation Strategy

### Phase 1: Exact Matching (Linear)

Replace recursive CTE with hash-based exact matching:

- Email normalization: `lower(trim(email))`
- Phone normalization: `regexp_replace(phone, '[^0-9]', '')`
- Fast hash joins instead of recursive traversal

### Phase 2: Incremental Updates

Convert to incremental materialization:

- Only process new identifiers daily
- Merge with existing resolved identifiers
- Dramatically reduce processing volume

### Phase 3: Fuzzy Matching (Bounded)

Implement controlled fuzzy matching:

- Only on unmatched identifiers from Phase 1
- Process in smaller batches (10K records)
- Use LSH for approximate clustering

## Expected Performance Gains

- **Current**: O(n²) - 42M identifiers → memory errors
- **Linear approach**: O(n) - 42M identifiers → ~42M operations
- **Incremental**: O(Δn) - Only new identifiers → thousands daily

## Technical Requirements

1. **New macros** for linear clustering algorithms
2. **Incremental materialization** strategy
3. **Snowflake clustering keys** on identifier_value
4. **Batch processing** for large datasets
5. **Monitoring** for performance regression testing

## Success Criteria

- [ ] No memory errors with full dataset (25M+ contracts)
- [ ] Processing time reduced from hours to minutes
- [ ] Incremental daily runs complete in <30 minutes
- [ ] Maintains same identity resolution accuracy
- [ ] Scales linearly with data growth

## Related Issues

- Memory errors in production identity resolution
- Poor performance with large contract datasets
- Need for efficient incremental processing
