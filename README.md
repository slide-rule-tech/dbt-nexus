# Nexus dbt Package

The Nexus dbt package provides a standardized set of models and macros to
process, resolve, and model customer identity and event data from various
sources. It helps in creating a unified view of entities (like persons and
groups) and their interactions.

## Prerequisites

- dbt version >= 1.0.0 (Update if necessary based on features used)
- Your dbt project should be connected to a BigQuery data warehouse.

## Installation

1.  **Add the package to your `packages.yml`:**

    If you are installing this package from a Git repository (e.g., its public
    GitHub URL):

    ```yaml
    # packages.yml
    packages:
      - git: "https://github.com/your-username/nexus.git" # Replace with the actual Git URL
        version: 0.1.0 # Or the specific version/tag/branch you want to use
    ```

    If you are using it as a local submodule within your project (as discussed
    for monorepo setups):

    ```yaml
    # packages.yml
    packages:
      - local: path/to/your/nexus_submodule # e.g., ../../external_libs/nexus
    ```

2.  **Install the package:** Run the following command in your dbt project:
    ```bash
    dbt deps
    ```

## Configuration

To use the Nexus package, you need to configure certain variables in your own
dbt project's `dbt_project.yml` file.

### 1. Define `sources` Variable

The Nexus package is designed to be source-agnostic. You must tell it what data
sources it should process and what kinds of entities each source provides. This
is done by defining a `sources` variable under the `vars:` section.

**Structure:** The `sources` variable should be a list of dictionaries, where
each dictionary represents a source system.

```yaml
# In your dbt_project.yml
vars:
  sources:
    - name: "your_source_system_A" # e.g., "salesforce", "segment", "manual_uploads"
      # For each entity type your package handles, indicate if this source provides it.
      # The entity types your package macros look for might include:
      # events, persons, groups, memberships, etc.
      # Adjust the flags below based on what your source provides and what nexus macros expect.
      events: true
      persons: true
      groups: false
      memberships: true
      # Add any other custom flags your package might use to toggle processing for a source.

    - name: "your_source_system_B"
      events: true
      persons: false
      groups: true
      memberships: false
      # ... other flags
```

**Naming Convention for Source Models:** The Nexus package will dynamically look
for dbt models in your project that follow a specific naming convention based on
the `name` you provide in the `sources` variable and the entity type. For
example, if you define a source with `name: "salesforce"` and `persons: true`,
the package will look for a model named `salesforce_person_identifiers` and
potentially `salesforce_person_traits` (or similar, depending on the specific
macros in the Nexus package). Ensure your project includes these source-specific
staging models with the expected columns.

### 2. Model Configuration (Optional)

You can configure models from the `nexus` package in your own `dbt_project.yml`
as well. For example, to change the materialization of all models in the `nexus`
package:

```yaml
# In your dbt_project.yml
models:
  nexus: # This should match the 'name' of the nexus package
    +materialized: table # Example: materialize all nexus models as tables
    # You can also specify subdirectories if needed:
    # final_tables:
    #   +materialized: table
```

By default, models in the `nexus` package will be created in a schema named
`nexus` (or the schema configured for your target if it overrides this).

## Basic Usage

Once installed and configured, you can reference the public models from the
Nexus package in your own dbt models using the `ref()` function.

For example, to select from the unified persons table:

```sql
-- your_model.sql
select
    person_id,
    email,
    -- ... other columns
from {{ ref('nexus_persons') }} -- Assuming nexus_persons is a public model
where ...
```

## Contributing

If you are contributing to the Nexus package itself:

- Note that the package is designed to be source-agnostic. Source-specific
  configurations and models (like `models/sources/`) should not be committed to
  the package repository.
- When developing the package locally, you may need to define dummy `vars` in
  your local `dbt_project.yml` or use command-line `--vars` to allow models to
  compile, as the package itself will not define specific sources.

---

This README provides a starting point. You should add more details about
specific public models, macros, and advanced configuration options as your
package evolves.
