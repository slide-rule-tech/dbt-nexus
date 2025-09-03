---
title: Quickstart Guide
tags: [quickstart, getting-started, setup, installation]
summary:
  Get up and running with dbt-nexus quickly with step-by-step guides for
  installation, setup, and configuration.
---

# Quickstart Guide

Welcome to the dbt-nexus quickstart guide! This section provides step-by-step
instructions to get you up and running with the dbt-nexus package as quickly as
possible.

## What is dbt-nexus?

The [dbt-nexus package](https://github.com/sliderule-analytics/dbt-nexus)
provides a standardized set of models and macros to process, resolve, and model
customer identity and event data from various sources. It helps create a unified
view of entities (like persons and groups) and their interactions.

## Quickstart Path

Follow these guides in order for the fastest path to success:

### 1. Initialize a New dbt Project

**[dbt-init.md](dbt-init.md)** - Set up a new dbt project following best
practices:

- Data warehouse setup (BigQuery example)
- Virtual environment configuration
- dbt installation and configuration
- Project verification

### 2. Install and Configure dbt-nexus

**[dbt-nexus-setup.md](dbt-nexus-setup.md)** - Install and configure the
dbt-nexus package:

- Installation methods (submodule vs GitHub)
- Demo data setup and exploration
- Schema configuration
- Alias setup for easy access

## What You'll Learn

By following these quickstart guides, you'll:

- ✅ **Set up a production-ready dbt project** with proper virtual environments
  and security
- ✅ **Install the dbt-nexus package** using the method that fits your workflow
- ✅ **Explore demo data** to understand the package's capabilities
- ✅ **Configure schemas** for organized data warehouse structure
- ✅ **Create aliases** for easy access to nexus models
- ✅ **Understand the data flow** from raw sources to final unified tables

## Prerequisites

Before starting, ensure you have:

- **Python 3.7+** installed
- **Git** for version control
- **Access to a data warehouse** (BigQuery, Snowflake, PostgreSQL, etc.)
- **Basic familiarity** with dbt concepts

## Next Steps

After completing the quickstart guides:

1. **Configure your data sources** - Set up your own data sources following the
   package's naming conventions
2. **Explore the tutorials** - Dive deeper into specific use cases and advanced
   features
3. **Read the reference documentation** - Understand all available models,
   macros, and configuration options
4. **Join the community** - Get help and share your experiences

## Getting Help

- 📚 **Complete Documentation**:
  [https://sliderule-analytics.github.io/dbt-nexus](https://sliderule-analytics.github.io/dbt-nexus)
- 🐛 **Report Issues**:
  [GitHub Issues](https://github.com/sliderule-analytics/dbt-nexus/issues)
- 💬 **Community**: [dbt Community Slack](https://community.getdbt.com/)

---

**Ready to get started?** Begin with [dbt-init.md](dbt-init.md) to set up your
dbt project, then move on to [dbt-nexus-setup.md](dbt-nexus-setup.md) to install
and configure the package.
