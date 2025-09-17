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

dbt-nexus is a comprehensive dbt package that helps you:

- **🔗 Resolve identities** across multiple data sources and systems
- **📊 Track events** with standardized event logging that creates actionable
  timelines
- **👥 Manage entities** including persons, groups, and their relationships
- **🏷️ Handle states** with timeline-based state management
- **⚡ Scale efficiently** with incremental processing and optimized queries
- **🎯 Drive operations** - support teams, sales teams, and AI tools get
  complete customer context

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
- Template sources configuration (Gmail, Google Calendar)
- Schema configuration and final table aliases
- Demo data exploration

## What You'll Learn

By following these quickstart guides, you'll:

- ✅ **Set up a production-ready dbt project** with proper virtual environments
  and security
- ✅ **Install the dbt-nexus package** using the method that fits your workflow
- ✅ **Configure template sources** like Gmail and Google Calendar with simple
  variables
- ✅ **Set up final table aliases** for easy model referencing
- ✅ **Configure schemas** for organized data warehouse structure
- ✅ **Understand the data flow** from raw sources to final unified tables
- ✅ **Explore unified customer data** across all your integrated sources

## Prerequisites

Before starting, ensure you have:

- **Python 3.7+** installed
- **Git** for version control
- **Access to a data warehouse** (BigQuery, Snowflake, PostgreSQL, etc.)
- **Basic familiarity** with dbt concepts
- **Data sources configured** (optional - can use demo data initially)

## Next Steps

After completing the quickstart guides:

1. **Enable template sources** - Configure Gmail, Google Calendar, or other
   [template sources](../template-sources/) for instant integration
2. **Set up your ETL pipeline** - Configure the Nexus ETL pipeline for data
   syncing
3. **Build custom models** - Create analytics models using the unified nexus
   data
4. **Explore advanced features** - Dive into identity resolution and state
   management
5. **Scale to production** - Set up incremental processing and monitoring

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
