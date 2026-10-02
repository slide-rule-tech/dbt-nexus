{#-
  Classify a Gmail delivery status notification (DSN) from its snippet.

  The Gmail API's message payload carries no body for these messages — only
  `headers` and a ~200-character `snippet` — so the RFC 3464 machine-readable
  `Status:` field is unavailable. Permanence is therefore judged from the
  snippet with an allow-list of permanent evidence and a deny-list that
  OVERRIDES it. Gating on a `5.x.x` code alone is not enough: the code often
  falls outside the snippet truncation (roughly two thirds of real permanent
  failures carry no code in the snippet at all).

    permanent evidence   "Address not found" (Gmail's own verdict for a
                         non-existent address or non-resolving domain),
                         "This is a permanent error" / "permanent failure"
                         (RFC-style wording other MTAs use), or any 5.x.x
                         enhanced status code.

    deny (wins)          4.x.x codes, "Delivery incomplete", "temporar…",
                         "will keep trying", "Message delayed" — genuinely
                         transient; plus permanent-LOOKING shapes that do not
                         mean the address is dead: "Message blocked" /
                         "Recipient address rejected" (550 5.4.1 is a policy or
                         sender-reputation decision — it says more about us
                         than about them), "did not accept our request" (no
                         status code at all), mailbox-full / over-quota (the
                         mailbox exists), and Google Groups' "may not exist,
                         or you may not have permission to post".

  The deny-list deliberately errs toward NOT flagging: a false negative costs
  one bounce, a false positive silently deletes a reachable human from
  outreach.

  Both macros take a SQL expression for the (already HTML-decoded) snippet and
  return a SQL expression. A NULL snippet classifies as not permanent.
-#}

{% macro gmail_bounce_smtp_status(snippet_expr) -%}
  {%- if target.type == 'bigquery' -%}
  REGEXP_EXTRACT({{ snippet_expr }}, r'\b(5\.\d{1,3}\.\d{1,3})\b')
  {%- else -%}
  regexp_extract({{ snippet_expr }}, '\b(5\.\d{1,3}\.\d{1,3})\b', 1)
  {%- endif -%}
{%- endmacro %}

{% macro gmail_bounce_is_permanent(snippet_expr) -%}
  {%- set r = 'r' if target.type == 'bigquery' else '' -%}
  {%- set s = 'COALESCE(' ~ snippet_expr ~ ", '')" -%}
  (
    (
      regexp_contains(lower({{ s }}), {{ r }}'address not found')
      or regexp_contains(lower({{ s }}), {{ r }}'this is a permanent error|permanent failure')
      or regexp_contains({{ s }}, {{ r }}'\b5\.\d{1,3}\.\d{1,3}\b')
    )
    and not (
      regexp_contains(
        lower({{ s }}),
        {{ r }}'delivery incomplete|temporar|will keep trying|message delayed|message blocked|recipient address rejected|did not accept our request|may not have permission to post|over quota|quota exceeded|mailbox is full'
      )
      or regexp_contains({{ s }}, {{ r }}'\b4\.\d{1,3}\.\d{1,3}\b')
    )
  )
{%- endmacro %}
