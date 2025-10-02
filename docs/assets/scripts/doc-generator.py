#!/usr/bin/env python3
"""
Documentation Generator for dbt-nexus

Automatically generates and updates documentation from dbt project files.
This script helps maintain consistency and reduces manual documentation overhead.
"""

import os
import re
import yaml
from pathlib import Path
from typing import Dict, List, Optional
import argparse

class DbtNexusDocGenerator:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.docs_root = self.project_root / "docs"
        self.models_root = self.project_root / "models"
        self.macros_root = self.project_root / "macros"
        
    def generate_model_reference(self, model_path: Path) -> str:
        """Generate reference documentation for a dbt model."""
        model_name = model_path.stem
        
        # Read the model file to extract documentation
        with open(model_path, 'r') as f:
            content = f.read()
        
        # Extract config block
        config_match = re.search(r'{{[\s]*config\((.*?)\)[\s]*}}', content, re.DOTALL)
        config = config_match.group(1) if config_match else ""
        
        # Extract description from schema.yml if exists
        description = self._get_model_description(model_name)
        
        # Generate documentation
        doc_content = f"""---
title: {model_name} Reference
tags: [reference, models, auto-generated]
summary: Auto-generated reference for {model_name} model
---

# {model_name} Reference

{description or f"Reference documentation for the {model_name} model."}

## Model Configuration

```sql
{{{{ config(
{config}
) }}}}
```

## Dependencies

{self._extract_dependencies(content)}

## Usage Example

```sql
SELECT * FROM {{{{ ref('{model_name}') }}}}
```

## Related Documentation

- [Model Index](./index.md)
- [Package Overview](../../index.md)

---
*This documentation was auto-generated. To update, modify the source model or run the doc generator.*
"""
        return doc_content
    
    def generate_macro_reference(self, macro_path: Path) -> str:
        """Generate reference documentation for a dbt macro."""
        macro_name = macro_path.stem
        
        with open(macro_path, 'r') as f:
            content = f.read()
        
        # Extract macro definition and documentation
        macro_def = self._extract_macro_definition(content)
        doc_comment = self._extract_macro_docs(content)
        
        doc_content = f"""---
title: {macro_name} Macro Reference
tags: [reference, macros, auto-generated]
summary: Auto-generated reference for {macro_name} macro
---

# {macro_name} Macro Reference

{doc_comment or f"Reference documentation for the {macro_name} macro."}

## Definition

```sql
{macro_def}
```

## Usage

```sql
{{{{ {macro_name}(parameter1, parameter2) }}}}
```

## Related Documentation

- [Macro Index](./index.md)
- [Package Overview](../../index.md)

---
*This documentation was auto-generated. To update, modify the source macro or run the doc generator.*
"""
        return doc_content
    
    def _get_model_description(self, model_name: str) -> Optional[str]:
        """Extract model description from schema.yml files."""
        # Look for schema.yml files in the models directory
        for schema_file in self.models_root.rglob("*.yml"):
            with open(schema_file, 'r') as f:
                try:
                    schema_data = yaml.safe_load(f)
                    if 'models' in schema_data:
                        for model in schema_data['models']:
                            if model.get('name') == model_name:
                                return model.get('description', '')
                except yaml.YAMLError:
                    continue
        return None
    
    def _extract_dependencies(self, content: str) -> str:
        """Extract ref() calls from model content."""
        refs = re.findall(r'ref\([\'"]([^\'"]+)[\'"]\)', content)
        if refs:
            return "### Upstream Models\n" + "\n".join([f"- `{ref}`" for ref in refs])
        return "No direct dependencies found."
    
    def _extract_macro_definition(self, content: str) -> str:
        """Extract the main macro definition."""
        macro_match = re.search(r'({%\s*macro.*?%}.*?{%\s*endmacro\s*%})', content, re.DOTALL)
        return macro_match.group(1) if macro_match else "Macro definition not found."
    
    def _extract_macro_docs(self, content: str) -> str:
        """Extract documentation comments from macro."""
        # Look for {# ... #} comments at the top of the file
        doc_match = re.search(r'{\#(.*?)\#}', content, re.DOTALL)
        return doc_match.group(1).strip() if doc_match else ""
    
    def generate_all_docs(self):
        """Generate documentation for all models and macros."""
        print("🚀 Generating dbt-nexus documentation...")
        
        # Generate model references
        models_generated = 0
        for model_file in self.models_root.rglob("*.sql"):
            if model_file.stem.startswith('_'):
                continue  # Skip private models
            
            doc_content = self.generate_model_reference(model_file)
            doc_path = self.docs_root / "reference" / "models" / f"{model_file.stem}.md"
            doc_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(doc_path, 'w') as f:
                f.write(doc_content)
            models_generated += 1
        
        # Generate macro references  
        macros_generated = 0
        for macro_file in self.macros_root.rglob("*.sql"):
            if macro_file.stem.startswith('_'):
                continue  # Skip private macros
            
            doc_content = self.generate_macro_reference(macro_file)
            doc_path = self.docs_root / "reference" / "macros" / f"{macro_file.stem}.md"
            doc_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(doc_path, 'w') as f:
                f.write(doc_content)
            macros_generated += 1
        
        print(f"✅ Generated {models_generated} model references")
        print(f"✅ Generated {macros_generated} macro references")
        print(f"📖 Documentation available at: {self.docs_root}")

def main():
    parser = argparse.ArgumentParser(description='Generate dbt-nexus documentation')
    parser.add_argument('--project-root', default='.', help='Path to dbt project root')
    args = parser.parse_args()
    
    generator = DbtNexusDocGenerator(args.project_root)
    generator.generate_all_docs()

if __name__ == "__main__":
    main()
