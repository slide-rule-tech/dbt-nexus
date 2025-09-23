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
- Dynamic column handling in `nexus_events` with optional field support
- Cross-database column name case compatibility (Snowflake uppercase vs others
  lowercase)
- Strong typing for all event columns with automatic NULL handling for missing
  fields
- **NEW**: Comprehensive data quality testing with 37 uniqueness and not-null
  tests across all nexus models
- **NEW**: Troubleshooting documentation with diagnostic queries and common
  solutions
- **NEW**: Testing reference documentation covering all model validations
- **NEW**: Role-based ID generation for proper multi-role entity handling
- **NEW**: Source data deduplication patterns for handling duplicate raw data
- **NEW**: Composite key testing for edge relationship validation

### Changed

- **BREAKING**: Identity resolution performance dramatically improved through
  edge deduplication
- `create_identifier_edges` macro now deduplicates edges using surrogate keys
  for massive performance gains
- Improved recursive CTE performance limits
- Enhanced incremental model strategies
- Identity resolution now scales linearly with unique entities rather than total
  events
- `nexus_events` model now uses dynamic column detection and strong typing
- Event column types now enforced: `value`/`significance` as FLOAT, timestamps
  as TIMESTAMP, strings as VARCHAR
- **BREAKING**: Standardized all ID field naming across models:
  - `id` → `person_identifier_id`, `group_identifier_id`,
    `membership_identifier_id`
  - `trait_id` → `person_trait_id`, `group_trait_id`
  - Added `state_id` to state management models
- **BREAKING**: Updated `create_nexus_id` macro usage across all identity
  resolution, final tables, and source models
- **BREAKING**: Enhanced participant ID generation to include role for proper
  multi-role handling
- **BREAKING**: Updated composite key test syntax from array format to
  concatenated string format

### Fixed

- **Critical**: Identity resolution performance bottleneck causing 10+ minute
  execution times
- Memory issues with large identity resolution datasets
- Edge explosion problem in high-frequency entity scenarios (26,000+ events per
  entity)
- Column type inconsistencies in `nexus_events` union operations
- Cross-database column name case sensitivity issues in
  `dbt_utils.union_relations`
- Missing optional columns now properly handled with typed NULL values
- **Critical**: Massive duplicate ID issues across all nexus models (99.96%
  duplicate reduction)
- **Critical**: Google Calendar source data duplicates causing 2,455+ duplicate
  person identifiers
- **Critical**: Group identifier duplicates from multiple employees at same
  domain in same event
- **Critical**: Membership identifier duplicates from same person-group
  combinations with different roles
- **Critical**: Participant ID duplicates when same entity has multiple roles in
  same event
- Edge relationship test failures due to incorrect composite key syntax
- Missing role inclusion in ID generation causing entity role conflicts
- Source data deduplication issues in Google Calendar attendee processing

### Performance Improvements

- Identity resolution edge creation: Hours → 3-5 seconds
- Recursive resolution: 12+ minutes → 4-5 seconds
- Edge reduction: 1.8M duplicate edges → 790 unique edges (99.96% reduction)
- Memory usage: Linear scaling vs quadratic explosion
- **Data Quality**: Duplicate ID reduction across all models:
  - nexus_person_identifiers: 2,455 duplicates → 1 duplicate (99.96% reduction)
  - nexus_group_identifiers: 2,640 duplicates → 0 duplicates (100% reduction)
  - nexus_membership_identifiers: 2,454 duplicates → 0 duplicates (100%
    reduction)
  - nexus_group_participants: 3,907 duplicates → 0 duplicates (100% reduction)
  - nexus_person_participants: All duplicates eliminated (100% reduction)

### Technical Details

**Edge Deduplication Algorithm**:

- Added surrogate key-based deduplication in `create_identifier_edges` macro
- Uses `generate_surrogate_key([type_a, value_a, type_b, value_b])` for
  uniqueness
- Eliminates cartesian product explosion in high-frequency entity scenarios
- Preserves all semantic relationships while removing redundant processing

**ID Standardization and Uniqueness Fixes**:

- **Standardized create_nexus_id Usage**: Updated all identity resolution, final
  tables, and source models to use consistent `create_nexus_id` macro with
  proper entity type prefixes
- **Role-Based ID Generation**: Enhanced ID generation to include role
  information preventing same-entity multi-role conflicts:
  - Person identifiers:
    `create_nexus_id('person_identifier', ['event_id', 'email', 'role', 'occurred_at'])`
  - Group identifiers:
    `create_nexus_id('group_identifier', ['event_id', 'domain', 'role', 'occurred_at'])`
  - Participant IDs:
    `create_nexus_id(entity_type ~ '_participant', ['event_id', entity_type ~ '_id', 'role'])`
- **Source Data Deduplication**: Added GROUP BY clauses to handle duplicate raw
  data:
  - Google Calendar attendee processing:
    `GROUP BY event_id, email, is_optional, occurred_at`
  - Group domain processing:
    `GROUP BY event_id, domain, is_optional, occurred_at`
- **Macro Updates**: Updated `process_entity_identifiers`,
  `process_entity_traits`, `finalize_participants`, and `common_state_fields`
  macros for consistent field naming
- **Test Configuration**: Fixed composite key test syntax from array format to
  concatenated string format for proper validation

**Dynamic Column Handling in nexus_events**:

- Compile-time column detection using `adapter.get_columns_in_relation()`
- Cross-database column name case handling (Snowflake uppercase vs others
  lowercase)
- Automatic column override generation with proper dbt type functions
- Missing columns automatically added as typed NULL values
- Supports optional schema fields: `significance`, `source_table`, `synced_at`

**Column Type Enforcement**:

- `value`, `significance`: `dbt.type_float()` (cross-database FLOAT)
- `occurred_at`, `synced_at`: `dbt.type_timestamp()` (cross-database TIMESTAMP)
- All other fields: `dbt.type_string()` (cross-database VARCHAR/TEXT)

**Impact**:

- Entities with 26,000+ events previously created 676M+ duplicate edges
- Now creates exactly 1 edge per unique identifier relationship
- Enables identity resolution on datasets with millions of events per entity
- Event model now works consistently across Snowflake, BigQuery, PostgreSQL,
  etc.
- Flexible schema handling allows source tables with varying column sets

**Comprehensive Data Quality Testing**:

- **37 Total Tests**: Complete coverage across all nexus models with uniqueness
  and not-null validations
- **Composite Key Testing**: Proper validation of edge relationships with
  concatenated string syntax
- **Diagnostic Tooling**: SQL queries to identify duplicate sources and root
  causes
- **Troubleshooting Documentation**: Step-by-step guides for resolving common
  duplicate scenarios
- **Test Categories**: Primary keys, composite keys, data integrity, and
  business rule compliance

**Documentation Enhancements**:

- **Troubleshooting Guide**: Comprehensive guide with real-world scenarios and
  SQL diagnostic queries
- **Testing Reference**: Complete documentation of all 37 tests with failure
  scenarios and solutions
- **LLM-Friendly Structure**: Diátaxis framework with clear headings and
  cross-references
- **Sample Queries**: Copy-paste diagnostic queries for identifying duplicate
  sources

**Backward Compatibility**:

- **BREAKING CHANGES**: ID field names updated across all models - migration
  required
- **BREAKING CHANGES**: Enhanced ID generation includes additional fields -
  existing IDs will change
- **BREAKING CHANGES**: Test syntax updated for composite keys - nexus.yml
  updates required
- Source model patterns remain consistent but with enhanced deduplication
- All macros maintain same interface but with improved internal logic

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
