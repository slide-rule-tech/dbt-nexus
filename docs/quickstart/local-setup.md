# Local Setup

This guide covers setting up the dbt-nexus package for local development and
ensuring the dbt poweruser extension works properly.

## Prerequisites

- Python 3.8+ with virtual environment
- dbt-core installed
- VS Code with dbt poweruser extension

## Project Configuration

### 1. dbt_project.yml Configuration

Ensure your `dbt_project.yml` includes the required `config-version`:

```yaml
name: "your_project_name"
version: "1.0.0"
config-version: 2 # Required for dbt poweruser extension

# ... rest of your configuration
```

### 2. VS Code Settings

Create a `.vscode/settings.json` file in your dbt project root to configure the
dbt poweruser extension:

```json
{
  "python.defaultInterpreterPath": "/path/to/your/venv/bin/python",
  "python.experiments.enabled": false,
  "dbt.dbtPythonPathOverride": "/path/to/your/venv/bin/python",
  "dbt.enableNewLineagePanel": true
}
```

**Important**: Replace `/path/to/your/venv/bin/python` with the actual path to
your Python virtual environment where dbt is installed.

### 3. Virtual Environment Setup

Create a `.commands` file in your project root to set up environment aliases:

```bash
source /path/to/your/venv/bin/activate
alias edit="code ./ &>/dev/null &"
alias run="dbt run"
alias run-refresh="dbt run --full-refresh"
alias deploy="dbt run --full-refresh --target prod"
alias run-nexus="dbt run --select package:nexus"
```

## Troubleshooting

### dbt Poweruser Extension Not Working

If the dbt poweruser extension isn't working:

1. **Check config-version**: Ensure `config-version: 2` is in your
   `dbt_project.yml`
2. **Verify Python path**: Make sure the `dbt.dbtPythonPathOverride` in VS Code
   settings points to the correct Python environment
3. **Test dbt installation**: Run `dbt --version` from your project directory to
   ensure dbt is accessible
4. **Reload VS Code**: Restart VS Code or reload the dbt poweruser extension

### ModuleNotFoundError: No module named 'dbt'

This error typically occurs when:

- The virtual environment isn't properly activated
- The VS Code settings point to the wrong Python environment
- dbt isn't installed in the specified Python environment

**Solution**: Update the `dbt.dbtPythonPathOverride` in your
`.vscode/settings.json` to point to the correct Python environment where dbt is
installed.
