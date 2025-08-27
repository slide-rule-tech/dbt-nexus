---
title: Changelog
tags: [changelog, releases, updates]
summary: All notable changes to the dbt-nexus package
---

# Changelog

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

### Changed

- Improved recursive CTE performance limits
- Enhanced incremental model strategies

### Fixed

- Memory issues with large identity resolution datasets

## [0.1.0] - 2024-12-XX

### Added

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
