---
title: Changelog
tags: [changelog, releases, updates]
summary: All notable changes to the dbt-nexus package
---

All notable changes to the dbt-nexus package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Comprehensive documentation with MkDocs
- LLM-friendly context pack for AI assistance
- State management with derived states
- Cross-database compatibility (Snowflake/BigQuery)
- Edge deduplication in identity resolution algorithm
- Complete identity resolution algorithm documentation with real performance
  metrics
- Source identifier formatting documentation with `unpivot_identifiers` macro
  examples

### Changed

- **BREAKING**: Identity resolution performance dramatically improved through
  edge deduplication
- `create_identifier_edges` macro now deduplicates edges using surrogate keys
  for massive performance gains
- Improved recursive CTE performance limits
- Enhanced incremental model strategies
- Identity resolution now scales linearly with unique entities rather than total
  events

### Fixed

- **Critical**: Identity resolution performance bottleneck causing 10+ minute
  execution times
- Memory issues with large identity resolution datasets
- Edge explosion problem in high-frequency entity scenarios (26,000+ events per
  entity)

### Performance Improvements

- Identity resolution edge creation: Hours → 3-5 seconds
- Recursive resolution: 12+ minutes → 4-5 seconds
- Edge reduction: 1.8M duplicate edges → 790 unique edges (99.96% reduction)
- Memory usage: Linear scaling vs quadratic explosion

### Technical Details

**Edge Deduplication Algorithm**:

- Added surrogate key-based deduplication in `create_identifier_edges` macro
- Uses `generate_surrogate_key([type_a, value_a, type_b, value_b])` for
  uniqueness
- Eliminates cartesian product explosion in high-frequency entity scenarios
- Preserves all semantic relationships while removing redundant processing

**Impact**:

- Entities with 26,000+ events previously created 676M+ duplicate edges
- Now creates exactly 1 edge per unique identifier relationship
- Enables identity resolution on datasets with millions of events per entity

**Backward Compatibility**:

- No changes required to existing source models
- All `*_person_identifiers`, `*_group_identifiers` tables work unchanged
- Event participation and final entity tables maintain identical output schema

## [0.1.0] - 2024-12-XX

### Initial Features

- Initial release of dbt-nexus package
- Core identity resolution for persons and groups
- Event logging with identifier and trait extraction
- Basic state management capabilities
- Source-agnostic adapter pattern
- Incremental processing support

### Models

- `nexus_events` - Unified event log
- `nexus_persons` - Resolved person entities
- `nexus_groups` - Resolved group entities
- `nexus_states` - Timeline-based state tracking

### Macros

- `resolve_identifiers()` - Core identity resolution logic
- `derived_state()` - Derived state creation
- `process_identifiers()` - Identifier extraction and normalization
- `event_filter()` - Incremental event filtering

---

## Release Notes Format

Each release includes:

### Added ✨

New features and capabilities

### Changed 🔄

Changes to existing functionality

### Deprecated ⚠️

Features that will be removed in future versions

### Removed 🗑️

Features removed in this version

### Fixed 🐛

Bug fixes and corrections

### Security 🔒

Security-related changes

---

## Migration Guides

When breaking changes occur, detailed migration guides will be provided in the
release notes.
