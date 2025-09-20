# Nexus dbt Package

The Nexus dbt package provides a standardized set of models and macros to
process, resolve, and model customer identity and event data from various
sources. It helps in creating a unified view of entities (like persons and
groups) and their interactions.

## 📖 Documentation

**📚 Complete Documentation**:
[https://sliderule-analytics.github.io/dbt-nexus](https://slide-rule-tech.github.io/dbt-nexus)  
**📖 Blog Post**:
[Dbt-Nexus - Data Beyond Dashboards](https://www.slideruleanalytics.com/blog/dbt-nexus-data-beyond-dashboards)

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

### 1. Recursion Control (`nexus_max_recursion`)

The Nexus package uses recursive CTEs for entity resolution. To prevent runaway
recursion and improve performance, you can control the maximum recursion depth
using the `nexus_max_recursion` variable.

- **Default:** The package sets `nexus_max_recursion: 5` by default.
- **Override:** You can override this value in your own project's
  `dbt_project.yml`:

```yaml
vars:
  nexus_max_recursion: 5 # Set to your preferred recursion limit
```

This variable is used in all identity resolution models and macros that perform
recursive CTEs, such as `nexus_resolved_person_identifiers` and
`nexus_resolved_group_identifiers`.

### 2. Define `sources` Variable

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

### 3. Model Configuration (Optional)

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

### Git Workflow

When making changes to the package:

1. **Create a Feature Branch**

   ```bash
   cd external_libs/dbt-nexus
   git checkout -b feature/your-feature-name
   ```

2. **Make Your Changes**

   - Make your code changes
   - Test your changes locally
   - Update documentation as needed

3. **Commit and Push**

   ```bash
   git add .
   git commit -m "Your descriptive commit message"
   git push origin feature/your-feature-name
   ```

4. **Create a Pull Request**

   - Create a PR on the dbt-nexus repository
   - Request review from team members
   - Address any feedback

5. **After PR Merge**
   - Update the submodule reference in the main project:
   ```bash
   cd ../..  # back to main project
   git submodule update --remote external_libs/dbt-nexus
   git add external_libs/dbt-nexus
   git commit -m "Update dbt-nexus submodule to latest main"
   git push
   ```

This will:

1. Pull the latest changes from the dbt-nexus repository
2. Update your main project's reference to point to the latest commit
3. Commit and push this reference update

---

This README provides a starting point. You should add more details about
specific public models, macros, and advanced configuration options as your
package evolves.
