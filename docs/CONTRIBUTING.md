# Contributing to dbt-nexus

Thanks for your interest in contributing to dbt-nexus! This guide will help you
get started.

## 🚀 Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a feature branch** for your changes
4. **Make your changes** following our guidelines
5. **Test your changes** thoroughly
6. **Submit a pull request**

## 📋 Types of Contributions

### 🐛 Bug Reports

- Use GitHub Issues with the "bug" label
- Include reproduction steps and expected vs actual behavior
- Provide sample data/queries when possible

### ✨ Feature Requests

- Use GitHub Issues with the "enhancement" label
- Describe the use case and proposed solution
- Consider backward compatibility

### 📖 Documentation

- Fix typos, improve clarity, add examples
- Use the documentation templates in `docs/_templates/`
- Follow the Diátaxis framework (tutorials, how-tos, reference, explanations)

### 🔧 Code Changes

- Follow dbt best practices
- Add tests for new functionality
- Update documentation for changes
- Maintain backward compatibility when possible

## 🛠️ Development Setup

### Prerequisites

- dbt Core >= 1.0.0
- Python 3.8+
- Snowflake or BigQuery access for testing

### Local Development

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/dbt-nexus.git
cd dbt-nexus

# Install development dependencies
pip install -r docs/scripts/requirements.txt

# Generate documentation
python docs/scripts/doc-generator.py --project-root .
python docs/scripts/llm-context-updater.py --project-root .

# Serve documentation locally
cd docs
mkdocs serve
```

## 📐 Guidelines

### Code Style

- Use descriptive model and macro names
- Add inline comments for complex logic
- Follow dbt naming conventions (snake_case)
- Include proper configuration blocks

### Documentation

- Write clear, concise descriptions
- Include usage examples
- Add troubleshooting sections
- Tag content appropriately for LLM consumption

### Testing

- Test with sample data before submitting
- Verify cross-database compatibility
- Check incremental model behavior
- Validate performance impact

## 🔄 Pull Request Process

1. **Create a clear title** describing your change
2. **Fill out the PR template** with details
3. **Link related issues** using keywords (fixes #123)
4. **Request review** from maintainers
5. **Address feedback** promptly
6. **Ensure CI passes** before merge

### PR Checklist

- [ ] Code follows style guidelines
- [ ] Tests added for new functionality
- [ ] Documentation updated
- [ ] Breaking changes documented
- [ ] Changelog updated

## 🏷️ Release Process

Releases follow semantic versioning:

- **Major (X.0.0)**: Breaking changes
- **Minor (X.Y.0)**: New features, backward compatible
- **Patch (X.Y.Z)**: Bug fixes, backward compatible

## 📞 Getting Help

- **Questions**: Use GitHub Discussions
- **Issues**: Create a GitHub Issue
- **Community chat**: [Community Slack](https://your-workspace.slack.com)

## 🏆 Recognition

Contributors are recognized in:

- Release notes
- README contributors section
- Special thanks in major releases

## 📄 License

By contributing, you agree that your contributions will be licensed under the
same license as the project (MIT License).

---

**Ready to contribute?** Start by checking our
[good first issues](https://github.com/sliderule/dbt-nexus/labels/good%20first%20issue)
or reviewing our [development to-dos](docs/to-dos/index.md)!
