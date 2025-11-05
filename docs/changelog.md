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

### Added ✨

- **Consistent Timestamp Fields**: Added standardized timestamp fields across core nexus models:
  - **Events** (`nexus_events`):
    - `_ingested_at` - When data was synced to the data warehouse (renamed from `synced_at`)
    - `_processed_at` - When dbt last built/ran the model
  - **Entities** (`nexus_entities`):
    - `_processed_at` - When dbt last built/ran the model
    - `_updated_at` - When entity data last changed (max of trait occurred_at)
    - `_created_at` - When entity was first created (min of identifier occurred_at)
    - `_last_merged_at` - When entity identifiers were last merged (max of edge timestamps)
    - `last_interaction_at` - Most recent event timestamp (no underscore prefix)
    - `first_interaction_at` - First event timestamp (no underscore prefix)
  - **Relationships** (`nexus_relationships`):
    - `_processed_at` - When dbt last built/ran the model
    - `_updated_at` - When relationship data last changed (max of declaration occurred_at)
    - `_created_at` - When relationship was first created (min of declaration occurred_at)
- **Schema Tests**: Added `not_null` tests with `severity: warn` for all timestamp fields to track data quality

### Changed 🔄

- **BREAKING**: `nexus_events.synced_at` renamed to `nexus_events._ingested_at` for consistency
  - Removed backward compatibility with `synced_at` - source models must now use `_ingested_at`
- **Entity Timestamps**: Updated `nexus_entities` to calculate `_last_merged_at` directly from `nexus_entity_identifiers` using `event_id` instead of joining with `nexus_entity_identifiers_edges` table

## [0.3.0] - 2025-10-09

### Major Architectural Refactor: Entity-Centric Model 🎯

This release represents a fundamental architectural shift from separate
person/group/membership models to a unified entity-centric architecture. This is
a **BREAKING CHANGE** that requires migration.

#### Added ✨

- **Unified Entity Model**: Single `nexus_entities` table with `entity_type`
  field replaces separate `nexus_persons` and `nexus_groups` tables
- **Universal Relationships**: `nexus_relationships` table replaces
  `nexus_memberships` with support for any entity-to-entity relationship type
- **Four-Layer Source Architecture**: Base → Normalized → Intermediate → Union
  structure for better developer experience and debugging
- **Entity-Centric Macros**:
  - `process_entity_identifiers()` - Unions all source entity identifiers (no
    entity_type parameter needed)
  - `process_entity_traits()` - Unions all source entity traits (no entity_type
    parameter needed)
  - `process_relationship_declarations()` - Unions all source relationship
    declarations
  - `resolve_entity_traits()` - Single-pass trait resolution for all entity
    types (50% reduction vs separate resolution)
  - `finalize_entities()` - Creates unified entities table from resolved
    identifiers and traits
  - `finalize_relationships()` - Creates relationships table from resolved
    declarations
- **Parallel Entity Resolution**: Separate identity resolution per entity_type
  for performance and debugging
  - `nexus_resolved_person_identifiers` - Resolves person entities
  - `nexus_resolved_group_identifiers` - Resolves group entities
  - Both use shared `nexus_entity_identifiers_edges` table with entity_type
    filtering
- **New ID Prefixes**: More descriptive prefixes for better identification
  - `ent_idfr_` - Entity identifiers (replaces `per_idfr_` and `grp_idfr_`)
  - `ent_tr_` - Entity traits (replaces `per_tr_` and `grp_tr_`)
  - `rel_decl_` - Relationship declarations (replaces `mem_idfr_`)
  - `rel_` - Resolved relationships (replaces `mem_`)
- **Template Source Migrations**: Gmail and Google Calendar fully migrated to
  new architecture
  - 26/26 tests passing for Gmail
  - 26/26 tests passing for Google Calendar
  - Four-layer structure implemented: Base → Normalized → Intermediate → Union
  - Person/group logic kept separate in intermediate layer for DevX
- **Configuration Enhancements**:
  - **Unified Configuration Structure**: All nexus settings now under single
    `nexus:` variable
  - `nexus.max_recursion` replaces `nexus_max_recursion`
  - `nexus.entity_types` replaces `nexus_entity_types`
  - `nexus.sources` dictionary replaces both `sources` list and duplicate
    `nexus.{source}.enabled` patterns
  - Single source of truth for all source configuration (enabled status, events,
    entities, relationships)
  - Backward compatibility maintained - macros check both old and new patterns

#### Changed 🔄

- **BREAKING**: `nexus_persons` and `nexus_groups` tables replaced by
  `nexus_entities` with `entity_type` column
  - Filter by `entity_type = 'person'` for person data
  - Filter by `entity_type = 'group'` for group data
  - Legacy views provided for backward compatibility in client projects
- **BREAKING**: `nexus_memberships` replaced by `nexus_relationships` with
  flexible relationship modeling
  - `relationship_type` field supports any relationship (not just memberships)
  - `entity_a_id` / `entity_b_id` replace `person_id` / `group_id`
  - Supports any entity type combinations (person-person, group-group, etc.)
- **BREAKING**: Source models now use 4 union layer models instead of 7 (43%
  reduction):
  - `{source}_events` - Event data
  - `{source}_entity_identifiers` - Unified person + group identifiers
  - `{source}_entity_traits` - Unified person + group traits
  - `{source}_relationship_declarations` - Replaces membership_identifiers
  - **Old structure** (deprecated): Separate `*_person_identifiers`,
    `*_person_traits`, `*_group_identifiers`, `*_group_traits`,
    `*_membership_identifiers` models
- **BREAKING**: ID prefixes changed for all entity-related records
  - Existing IDs will not match after migration
  - `create_nexus_id` macro updated with new prefixes
- **BREAKING**: Macro signatures simplified:
  - `process_entity_identifiers()` - No longer takes entity_type parameter
  - `process_entity_traits()` - No longer takes entity_type parameter
  - Filtering by entity_type happens within resolution macros
- **BREAKING**: Configuration structure completely redesigned in
  `dbt_project.yml`:
  - **Old**: Separate `nexus_max_recursion`, `nexus_entity_types`, and `sources`
    list variables
  - **New**: Unified `nexus` config with `max_recursion`, `entity_types`, and
    `sources` dictionary
  - Example:
    ```yaml
    nexus:
      max_recursion: 3
      entity_types: ["person", "group"]
      sources:
        gmail:
          enabled: true
          events: true
          entities: ["person", "group"]
          relationships: true
    ```
  - **Backward Compatibility**: Macros support both old and new patterns for
    gradual migration
- Identity resolution now filters by `entity_type` within unified
  `nexus_entity_identifiers_edges` table
  - Single edges table for all entity types (instead of separate person/group
    edges tables)
  - `entity_type` included in edge uniqueness hash to prevent collisions
- Trait resolution consolidated to single `nexus_resolved_entity_traits` model
  - Replaces separate `nexus_resolved_person_traits` and
    `nexus_resolved_group_traits`
  - More efficient single-pass resolution
- Edge creation macro updated to include `entity_type` in uniqueness hash
  - Prevents edge ID collisions between entity types with similar identifiers

#### Deprecated ⚠️

- Separate person/group/membership models throughout the pipeline
  - Legacy compatibility views provided in client projects:
    - `persons` view filters `nexus_entities WHERE entity_type = 'person'`
    - `groups` view filters `nexus_entities WHERE entity_type = 'group'`
    - `memberships` view filters
      `nexus_relationships WHERE relationship_type = 'membership'`
- Old macro signatures with entity_type parameters

#### Migration Guide 📋

**For Core Package Users (BREAKING - Migration Required)**:

See [v2-entities-relationships.md](migrations/v2-entities-relationships.md) for
complete migration guide.

**Key Steps**:

1. Update `dbt_project.yml` sources configuration
2. Migrate source models to four-layer structure
3. Update queries to use `nexus_entities` and `nexus_relationships`
4. Update ID prefix patterns in tests
5. Remove deprecated models

**For Client Projects**:

- Legacy views automatically created for smooth transition
- Update queries incrementally to use new tables
- No immediate action required

#### Performance Impact ⚡

- **Model count per source**: 7 → 4 models (43% reduction at union layer)
- **Identity resolution**: Parallel execution per entity_type for better
  performance
- **Trait resolution**: Single pass instead of per-type (50% model reduction)
- **Recursion optimization**: Set `nexus_max_recursion: 3` for large datasets
  (26k+ identifiers)
  - Without limit: 5-minute timeout on 26k identifiers
  - With limit: 19 seconds for person resolution, similar for groups
- **Edge table consolidation**: Single `nexus_entity_identifiers_edges` instead
  of separate person/group edges
- **Deduplication**: Built-in SELECT DISTINCT for attendee/recipient arrays

#### Data Quality Improvements 🛡️

- **Role-based ID generation**: Prevents duplicate IDs when same entity has
  multiple roles in one event
- **Attendee deduplication**: Handles duplicate entries in recipient/attendee
  arrays
- **Entity type filtering**: Prevents edge collisions between entity types
- **Comprehensive testing**: 26 tests per template source (Gmail, Google
  Calendar)
  - All ID prefix patterns validated
  - Entity type constraints enforced
  - Uniqueness and not-null tests for all union layer models

#### Template Sources Updated 📧📅

**Gmail Template Source**:

- Migrated to four-layer architecture
- 12 total models (1 base + 1 normalized + 6 intermediate + 4 union)
- 26/26 tests passing
- 26,600 identifiers processed (11k person, 15.6k group)
- Special handling for duplicate recipients in email arrays

**Google Calendar Template Source**:

- Migrated to four-layer architecture
- 12 total models (1 base + 1 normalized + 6 intermediate + 4 union)
- 26/26 tests passing
- 24,200 identifiers processed (14.9k person, 9.3k group)
- Special naming: `google_calendar_events_normalized`,
  `google_calendar_event_events`
- Deduplication for duplicate attendees in calendar events

#### Backward Compatibility ⚠️

- **Core Package**: NO backward compatibility - requires migration to v0.3.0
- **Client Projects**: Legacy views provided for gradual transition
  - Views automatically filter `nexus_entities` by entity_type
  - Views map old column names to new structure
- **Source Configuration**: Update vars structure in `dbt_project.yml`
- **Breaking Changes**: All queries using old table names must be updated

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
- **NEW**: Segment template source with comprehensive attribution and identity
  resolution
- **NEW**: UTM parameter and click ID tracking for attribution analysis
- **NEW**: Channel classification (paid, social, organic, referral, direct)
- **NEW**: Touchpoint modeling with Facebook and Google click ID support
- **NEW**: Attribution models template source with configurable attribution
  logic
- **NEW**: Last Facebook Click ID attribution model with window function
  approach

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
- **MIGRATION**: Segment source migrated from client-specific implementation to
  reusable template source with enabled configuration
- **MIGRATION**: Attribution models migrated from client-specific implementation
  to reusable template source with enabled configuration

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

**Segment Template Source Migration**:

- **Template Source Pattern**: Migrated Segment integration from client-specific
  implementation to reusable template source
- **Enabled Configuration**: All models now use
  `var('nexus', {}).get('segment', {}).get('enabled', false)` pattern
- **Attribution Features**: Complete UTM parameter and click ID tracking with
  channel classification
- **Touchpoint Modeling**: Facebook (fbclid) and Google (gclid) click ID support
- **Comprehensive Documentation**: Full template source documentation with
  configuration examples and troubleshooting guides
- **Migration Guide**: Step-by-step process for migrating from legacy sources to
  template sources

**Attribution Models Template Source Migration**:

- **Template Attribution Pattern**: Migrated attribution models from
  client-specific implementation to reusable template source
- **Enabled Configuration**: All attribution models now use
  `var('nexus', {}).get('attribution_models', {}).get('model_name', {}).get('enabled', false)`
  pattern
- **Last Facebook Click ID Model**: Complete fbclid attribution with window
  function approach for person-level tracking
- **Attribution Infrastructure**: Updated `nexus_attribution_model_results` to
  use new configuration structure
- **Comprehensive Documentation**: Full attribution models documentation with
  configuration examples and usage patterns
- **Attribution Logic**: Window function-based attribution with 90-day
  attribution window and touchpoint batch processing

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
