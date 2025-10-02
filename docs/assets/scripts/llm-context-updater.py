#!/usr/bin/env python3
"""
LLM Context Updater for dbt-nexus

Automatically updates the LLM context pack when models, macros, or configurations change.
This ensures the AI context stays current with the actual package implementation.
"""

import os
import re
import yaml
from pathlib import Path
from typing import Dict, List, Set
import json

class LLMContextUpdater:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.docs_root = self.project_root / "docs"
        self.context_file = self.docs_root / "llm" / "context-pack.md"
        
    def scan_project_structure(self) -> Dict:
        """Scan the project to extract current structure and components."""
        structure = {
            "models": {
                "event_log": [],
                "identity_resolution": [],
                "final_tables": [],
                "states": []
            },
            "macros": {
                "identity_resolution": [],
                "event_processing": [],
                "state_management": [],
                "utilities": []
            },
            "config_vars": []
        }
        
        # Scan models
        models_dir = self.project_root / "models"
        if models_dir.exists():
            for model_file in models_dir.rglob("*.sql"):
                model_name = model_file.stem
                
                # Categorize by path
                path_parts = model_file.relative_to(models_dir).parts
                if "event-log" in path_parts:
                    structure["models"]["event_log"].append(model_name)
                elif "identity-resolution" in path_parts:
                    structure["models"]["identity_resolution"].append(model_name)
                elif "final-tables" in path_parts:
                    structure["models"]["final_tables"].append(model_name)
                elif "states" in path_parts:
                    structure["models"]["states"].append(model_name)
        
        # Scan macros
        macros_dir = self.project_root / "macros"
        if macros_dir.exists():
            for macro_file in macros_dir.rglob("*.sql"):
                macro_name = macro_file.stem
                
                # Categorize by path
                path_parts = macro_file.relative_to(macros_dir).parts
                if "entity-resolution" in path_parts:
                    structure["macros"]["identity_resolution"].append(macro_name)
                elif "event-log" in path_parts:
                    structure["macros"]["event_processing"].append(macro_name)
                elif "states" in path_parts:
                    structure["macros"]["state_management"].append(macro_name)
                else:
                    structure["macros"]["utilities"].append(macro_name)
        
        # Scan configuration variables
        dbt_project = self.project_root / "dbt_project.yml"
        if dbt_project.exists():
            with open(dbt_project, 'r') as f:
                project_config = yaml.safe_load(f)
                if 'vars' in project_config:
                    structure["config_vars"] = list(project_config['vars'].keys())
        
        return structure
    
    def generate_updated_context(self, structure: Dict) -> str:
        """Generate updated context pack content based on current project structure."""
        
        # Generate model lists
        event_log_models = ", ".join([f"`{m}`" for m in structure["models"]["event_log"]])
        identity_models = ", ".join([f"`{m}`" for m in structure["models"]["identity_resolution"]])
        final_models = ", ".join([f"`{m}`" for m in structure["models"]["final_tables"]])
        state_models = ", ".join([f"`{m}`" for m in structure["models"]["states"]])
        
        # Generate macro lists
        identity_macros = ", ".join([f"`{m}()`" for m in structure["macros"]["identity_resolution"]])
        event_macros = ", ".join([f"`{m}()`" for m in structure["macros"]["event_processing"]])
        state_macros = ", ".join([f"`{m}()`" for m in structure["macros"]["state_management"]])
        utility_macros = ", ".join([f"`{m}()`" for m in structure["macros"]["utilities"]])
        
        # Generate config vars
        config_vars = ", ".join([f"`{v}`" for v in structure["config_vars"]])
        
        # Read current context file to preserve manual content
        current_content = ""
        if self.context_file.exists():
            with open(self.context_file, 'r') as f:
                current_content = f.read()
        
        # Extract sections that should be preserved (Mission, Gotchas, etc.)
        mission_match = re.search(r'## Mission\n\n(.*?)\n\n##', current_content, re.DOTALL)
        mission = mission_match.group(1) if mission_match else "Auto-updated mission content needed."
        
        gotchas_match = re.search(r'## Gotchas & Important Notes(.*?)\n\n##', current_content, re.DOTALL)
        gotchas = gotchas_match.group(1) if gotchas_match else "\n\nAuto-updated gotchas content needed."
        
        # Generate updated content
        updated_content = f"""---
title: dbt-nexus LLM Context Pack
tags: [llm, context, nexus, identity-resolution, auto-updated]
summary: Auto-updated compact briefing for LLMs about the dbt-nexus package.
---

# dbt-nexus LLM Context Pack

*Last updated: auto-generated on package scan*

## Mission

{mission}

## Core Concepts

### Primary Entities
- **Persons**: Individual entities with identifiers (email, phone, etc.) and traits (name, age, etc.)
- **Groups**: Organizational entities (companies, accounts) with their own identifiers and traits  
- **Events**: Timestamped actions/occurrences that generate identifiers, traits, and state changes
- **Memberships**: Relationships connecting persons to groups with optional roles

### Key Processes
- **Identity Resolution**: Recursive CTE-based deduplication using configurable matching rules
- **State Management**: Timeline-based state tracking with derived state capabilities
- **Event Processing**: Standardized event logging with identifier and trait extraction
- **Source Integration**: Adapter pattern for connecting any data source

## Architecture Layers

1. **Source Adapters**: Transform source data into standardized formats
2. **Event Log**: Core models for events, identifiers, traits
3. **Identity Resolution**: Deduplication logic producing resolved entities
4. **State Management**: Timeline tracking with derived states
5. **Final Tables**: Production-ready resolved entities

## Canonical Entry Points

### Key Models (Auto-detected)
- **Event Log**: {event_log_models}
- **Identity Resolution**: {identity_models}
- **Final Tables**: {final_models}
- **States**: {state_models}

### Essential Macros (Auto-detected)
- **Identity Resolution**: {identity_macros}
- **Event Processing**: {event_macros}
- **State Management**: {state_macros}
- **Utilities**: {utility_macros}

### Critical Configuration (Auto-detected)
- **Variables**: {config_vars}

## Source Integration Pattern

Sources must provide models following naming convention `{{source_name}}_{{entity_type}}_{{data_type}}`:
- Events: `{{source}}_events`
- Identifiers: `{{source}}_person_identifiers`, `{{source}}_group_identifiers`  
- Traits: `{{source}}_person_traits`, `{{source}}_group_traits`
- Memberships: `{{source}}_membership_identifiers`

## State Management

States follow format `{{namespace}}_{{subject}}[_{{qualifier}}]` (e.g., `billing_lifecycle`, `sliderule_app_installation`). Each state model tracks timeline changes with `state_entered_at`, `state_exited_at`, and `is_current` fields. Derived states combine multiple base states using timeline merging logic.

{gotchas}

## Quick Reference

### Common Tasks
- **Add new source**: Define in `sources` var, create `{{source}}_{{entity}}_{{type}}` models
- **Create custom state**: Make individual state model, add to `nexus_states` union
- **Debug identity resolution**: Check edge creation models for connectivity issues
- **Performance tuning**: Adjust recursion limits, review incremental strategies

### Troubleshooting
- **Missing identities**: Verify source model naming and schema compliance
- **Recursive CTE errors**: Check recursion settings and data quality
- **State timeline gaps**: Ensure events have proper `occurred_at` timestamps
- **Incremental issues**: Review `_ingested_at` values and watermark logic

## Links & References

- **Documentation**: `/docs/index.md`
- **Model Reference**: `/docs/reference/models/`
- **Macro Reference**: `/docs/reference/macros/`
- **Configuration Guide**: `/docs/getting-started/configuration.md`
- **Architecture Deep Dive**: `/docs/explanations/architecture.md`

---
*This context pack is auto-generated. Manual updates should be made to preserve custom content.*
"""
        
        return updated_content
    
    def update_context_pack(self):
        """Update the LLM context pack with current project structure."""
        print("🤖 Scanning project for LLM context updates...")
        
        structure = self.scan_project_structure()
        updated_content = self.generate_updated_context(structure)
        
        # Ensure directory exists
        self.context_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Write updated content
        with open(self.context_file, 'w') as f:
            f.write(updated_content)
        
        print(f"✅ Updated LLM context pack at: {self.context_file}")
        print(f"📊 Found: {len(structure['models']['event_log']) + len(structure['models']['identity_resolution']) + len(structure['models']['final_tables']) + len(structure['models']['states'])} models")
        print(f"🔧 Found: {sum(len(macros) for macros in structure['macros'].values())} macros")
        print(f"⚙️  Found: {len(structure['config_vars'])} config variables")

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Update LLM context pack for dbt-nexus')
    parser.add_argument('--project-root', default='.', help='Path to dbt project root')
    args = parser.parse_args()
    
    updater = LLMContextUpdater(args.project_root)
    updater.update_context_pack()

if __name__ == "__main__":
    main()
