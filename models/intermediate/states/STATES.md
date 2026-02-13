# 📘 State Naming Convention Guide — dbt-nexus

This document defines the naming convention for `state_name` values in the
`states` model of **dbt-nexus**.

Each row in the `states` table answers the question:

> **"What is the state of their `state_name`?"**  
> → **"The state of their `sliderule_app_installation` is `installed`."**

This convention ensures `state_name` values are:

- ✅ Descriptive but not redundant
- ✅ Consistent across domains
- ✅ Easy to query, document, and reason about

---

## ✅ Format

```text
<namespace>_<subject>[_qualifier]
```

### Components:

| Part                     | Description                                                                                     |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| `namespace`              | Domain or system prefix, e.g. `sliderule`, `google`, `ga4`, `billing`, `support`                |
| `subject`                | The object or concept whose state is being tracked, e.g. `app`, `profile`, `connection`, `plan` |
| `qualifier` _(optional)_ | Specifies the lifecycle or sub-track, e.g. `installation`, `lifecycle`, `status`, `progress`    |

---

## 🧾 Examples

| `state_name`                  | `state_value` examples                    | Interpretation                 |
| ----------------------------- | ----------------------------------------- | ------------------------------ |
| `sliderule_app_installation`  | `installed`, `uninstalled`, `deactivated` | State of the app installation  |
| `google_profile_connection`   | `connected`, `disconnected`, `none`       | OAuth connection status        |
| `google_analytics_connection` | `connected`, `disconnected`, `none`       | GA4 integration state          |
| `billing_lifecycle`           | `none`, `trialing`, `active`, `cancelled` | Billing state for the customer |
| `onboarding_progress`         | `invited`, `started`, `completed`         | Onboarding progress            |
| `support_ticket_status`       | `open`, `in_progress`, `resolved`         | Current support ticket status  |

---

## ✅ Writing Good `state_name`s

| Rule                                                  | ✅ Do                        | ❌ Avoid                                 |
| ----------------------------------------------------- | ---------------------------- | ---------------------------------------- |
| Use readable phrases: “What is the state of their X?” | `sliderule_app_installation` | `sliderule_app` (too vague)              |
| Use **nouns**, not verbs                              | `ga4_connection`             | `has_connected_ga4`                      |
| Be **specific**                                       | `billing_lifecycle`          | `status`                                 |
| Avoid repetition between name and value               | `connection` → `connected`   | `connection_status` → `connected_status` |
| Use consistent, lowercase `snake_case`                | `support_ticket_status`      | `SupportTicketStatus`, `supportStatus`   |

---

## 📁 File Naming Convention

State model files should follow this naming convention:

- **File name must match the `state_name`**: `{state_name}.sql`
- **Documentation files**: `{STATE_NAME}.md` (uppercase)

### Examples:

| State Name                    | SQL File                          | Documentation File               |
| ----------------------------- | --------------------------------- | -------------------------------- |
| `sliderule_app_installation`  | `sliderule_app_installation.sql`  | `SLIDERULE_APP_INSTALLATION.md`  |
| `google_analytics_connection` | `google_analytics_connection.sql` | `GOOGLE_ANALYTICS_CONNECTION.md` |
| `billing_lifecycle`           | `billing_lifecycle.sql`           | `BILLING_LIFECYCLE.md`           |

This ensures consistency and makes it easy to locate state models and their
documentation.

---

## 🧠 When to Use a Qualifier

Use a third token (`_installation`, `_connection`, `_lifecycle`, etc.) when:

- You need to distinguish between multiple state tracks for the same domain.
- A simple `namespace_object` would be ambiguous.

---

## 🛠 Suggested Tooling

### State Registry (YAML or Table)

Define allowed state tracks and values:

```yaml
- state_name: sliderule_app_installation
  allowed_values: [installed, uninstalled, deactivated]
  description: State of the Shopify app installation
```

## dbt Tests (Optional)

Implement tests to:

Assert state_value ∈ allowed_values for each state_name

Validate naming matches <namespace>\_<subject>[_qualifier] pattern

## 🧩 Example Usage

```text
-- Example row in the states model:
entity_id           = "abc_123"
state_name          = "billing_lifecycle"
state_value         = "trialing"
state_entered_at    = "2025-06-01"
state_exited_at     = NULL
is_current          = TRUE
```

This reads:

“The state of their billing lifecycle is trialing (currently).”

## 📚 Related Concepts

This naming convention differs from the event model, which uses object_action
format (e.g. app_installed).

Here, state_name defines the dimension, and state_value defines the position
within that dimension.
