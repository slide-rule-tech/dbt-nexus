---
title: How to Add or Update Documentation
tags: [how-to, docs, contribution]
summary:
  Step-by-step guide for keeping the package documentation organized,
  consistent, and LLM-friendly.
---

# How to Add or Update Documentation

This package uses **MkDocs + Material** with a Diátaxis-style layout. All docs
live in the `/docs/` directory and are auto-published to GitHub Pages.

**Important**: The `mkdocs.yml` configuration file is located in the **project
root directory**, not in the docs folder.

Follow this guide to add new docs or update existing ones.

---

## 1. Pick the Right Section

Organize new content based on intent:

- **Tutorials** → Step-by-step introductions for new users.
- **How-to** → Task-focused instructions (recipes).
- **Reference** → API details (macros, config options, CLI).
- **Explanations** → Background, design decisions, ADRs.
- **FAQ / Glossary** → Common Q&A and key term definitions.
- **LLM context pack** → Compact, structured context for machine readers.

---

## 2. Create a New Page

1. Add a new Markdown file in the correct subfolder, e.g.:
   `docs/how-to/add-new-source.md`
2. Always include **frontmatter** at the top:

```yaml
---
title: Adding a new source
tags: [how-to, sources, configuration]
summary: Step-by-step to register a new data source in this package.
---
```

## 3. Use clear headings (##, ###) so content is chunkable by LLMs

## 4. Update Navigation

Edit `mkdocs.yml` (located in the **project root directory**) and add your new
page to the nav section. Example:

```yaml
nav:
  - How-to:
      - Add a new source: how-to/add-new-source.md
```

## 5. Testing Your Changes

To test your documentation changes locally:

```bash
# From the project root directory (where mkdocs.yml is located):
mkdocs build --verbose --clean    # Build the site
mkdocs serve                      # Start development server at http://127.0.0.1:8000
```

**Note**: Always run MkDocs commands from the project root directory, not from
the docs folder.

## 6. Writing Guidelines

- Keep pages small (300–700 words) and focused on a single concept.
- Use headings liberally for easy skimming and chunking.
- Use code fences for SQL/Jinja examples.
- Cross-link to related pages (reference ↔ how-to ↔ explanation).
- Add new terms/questions to the Glossary & FAQ as they arise.
- Prefer Mermaid or ASCII diagrams; include a one-paragraph summary for each.
- Maintain stable anchors: avoid casually renaming headings, as LLMs and links
  rely on them.
