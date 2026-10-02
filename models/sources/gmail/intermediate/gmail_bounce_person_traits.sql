{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'person_traits', 'bounces']
) }}

{#-
  Delivery-failure ("bounce") traits for the FAILED RECIPIENT.

  A delivery status notification (DSN) is a message FROM the mail system TO
  one of our mailboxes, and `gmail_message_participants` therefore only ever
  sees `mailer-daemon@…` and the mailbox that received the report. The address
  that actually failed is NOT a participant — it lives in the
  `X-Failed-Recipients` header (and, in prose, in the body). This model is the
  one place that reads it, so the trait lands on the person who could not be
  reached rather than on the person who got told about it.

  WHY A HEADER AND NOT THE SNIPPET, for identity: `X-Failed-Recipients` is a
  machine-readable address list, so the recipient is parsed exactly, not scraped
  out of an English sentence. The snippet is used only to judge PERMANENCE
  (below), never to find the address.

  PERMANENCE. Only a permanent failure sets `address_invalid`. Gmail retries a
  transient failure for ~48h and the mailbox is usually fine, so treating a
  delay notice as a dead address would suppress outreach to live people. The
  Gmail API's message payload carries no body for these messages — only
  `headers` and a ~200-character `snippet` — and the RFC 3464 machine-readable
  `Status:` field lives in the body we do not have. So permanence is judged from
  the snippet, with an explicit allow-list of permanent evidence and a
  deny-list that OVERRIDES it:

    permanent evidence   "Address not found" (Gmail's own verdict for a
                         non-existent address or non-resolving domain),
                         "This is a permanent error" / "permanent failure"
                         (RFC-style wording other MTAs use), or any 5.x.x
                         enhanced status code.

    deny (wins)          4.x.x codes, "Delivery incomplete", "temporar…",
                         "will keep trying", "Message delayed" — genuinely
                         transient; plus three AMBIGUOUS shapes that are
                         permanent-looking but do not mean the address is
                         dead: "Message blocked" / "Recipient address
                         rejected" (a policy or sender-reputation decision —
                         550 5.4.1 says more about us than about them),
                         "did not accept our request" (no status code at all),
                         mailbox-full / over-quota (the mailbox exists), and
                         Google Groups' "may not exist, or you may not have
                         permission to post".

  The deny-list deliberately errs toward NOT flagging: a false negative costs
  one bounce, a false positive silently deletes a reachable human from
  outreach.

  SEMANTICS — this trait is a VERDICT, NOT A TOMBSTONE. `nexus_resolved_entity_traits`
  keeps the latest value per (entity, trait_name) ordered by `occurred_at`, so
  the newest signal wins and nothing is permanent. Two signals are emitted:

    address_invalid = 'true'   at the DSN's send time, for a permanent failure.
    address_invalid = 'false'  at the send time of any message the bounced
                               address itself SENT us. Receiving mail from an
                               address is positive evidence the mailbox is
                               live, so a restored mailbox clears itself on the
                               next inbound message with no manual
                               intervention.

  Because the resolution is by `occurred_at`, an inbound message from BEFORE
  the bounce correctly loses to the bounce, and one from after it correctly
  wins — ordering does the work, no windowing needed. Addresses that never
  bounced emit nothing at all, so `address_invalid IS NULL` means "no bounce
  history", which keeps the trait's blast radius to exactly the addresses it
  has evidence about.

  `address_invalid_at` and `address_invalid_reason` are emitted ONLY on failure
  rows: they describe the last observed permanent failure and are deliberately
  left standing after a recovery, so the history stays auditable. Read them
  together with `address_invalid`, which is the current verdict. The reason
  carries the SMTP enhanced status when the snippet exposed one plus the
  snippet verbatim, rather than a parsed-down category — the raw sentence is
  what a human needs to second-guess the classification above, and it cannot
  drift out of sync with a regex.

  MATERIALIZED AS A TABLE, not incrementally. Permanent failures are rare
  (tens of rows, not millions), and both legs need full history: a bounce that
  lands today must be able to find inbound mail from that address ingested
  years ago. An `_ingested_at` watermark would hide exactly that. The cost is
  one scan of `gmail_messages` per run.

  NOT COVERED: non-Google NDRs that omit `X-Failed-Recipients` (Exchange's
  "Undeliverable: …" shape) are not parsed; a failed send that never produced a
  Gmail DSN (mail sent through another provider entirely) is invisible here;
  and a non-resolving DOMAIN is recorded only against the individual mailbox,
  not as a group trait.
-#}

{%- set r = 'r' if target.type == 'bigquery' else '' -%}

with messages as (

    select
        m.message_id,
        m.sent_at,
        -- Already HTML-decoded upstream in gmail_messages_by_account, so
        -- "wasn&#39;t" is "wasn't" by the time the regexes below see it.
        m.snippet,
        m._ingested_at,
        {{ nexus.gmail_header_value('m.raw_record', 'x-failed-recipients') }} as x_failed_recipients
    from {{ ref('gmail_messages') }} m

),

dsn_messages as (

    select * from messages
    where x_failed_recipients is not null

),

-- X-Failed-Recipients is a comma-separated address list per RFC. Gmail sends
-- one DSN per failed recipient in practice, but do not rely on that.
failed_recipients as (

    select
        d.message_id,
        d.sent_at,
        d.snippet,
        d._ingested_at,
        -- Same normalizer the participant models use, so the identifier this
        -- trait attaches to is the identifier identity resolution already knows.
        {{ nexus.validate_and_normalize_email('TRIM(recipient)') }} as email
    from dsn_messages d,
    UNNEST(SPLIT(COALESCE(d.x_failed_recipients, ''), ',')) as {% if target.type == 'duckdb' %}t(recipient){% else %}recipient{% endif %}
    where TRIM(recipient) != ''

),

classified as (

    select
        fr.message_id,
        fr.sent_at,
        fr._ingested_at,
        fr.email,
        fr.snippet,
        {% if target.type == 'bigquery' -%}
        REGEXP_EXTRACT(fr.snippet, r'\b(5\.\d{1,3}\.\d{1,3})\b')
        {%- else -%}
        regexp_extract(fr.snippet, '\b(5\.\d{1,3}\.\d{1,3})\b', 1)
        {%- endif %} as smtp_status,
        (
            regexp_contains(lower(fr.snippet), {{ r }}'address not found')
            or regexp_contains(lower(fr.snippet), {{ r }}'this is a permanent error|permanent failure')
            or regexp_contains(fr.snippet, {{ r }}'\b5\.\d{1,3}\.\d{1,3}\b')
        ) as has_permanent_failure_evidence,
        (
            regexp_contains(
                lower(fr.snippet),
                {{ r }}'delivery incomplete|temporar|will keep trying|message delayed|message blocked|recipient address rejected|did not accept our request|may not have permission to post|over quota|quota exceeded|mailbox is full'
            )
            or regexp_contains(fr.snippet, {{ r }}'\b4\.\d{1,3}\.\d{1,3}\b')
        ) as has_transient_or_ambiguous_evidence
    from failed_recipients fr
    where fr.email is not null
      and fr.snippet is not null

),

permanent_failures as (

    select
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        message_id,
        email,
        sent_at,
        _ingested_at,
        smtp_status,
        snippet
    from classified
    where has_permanent_failure_evidence
      and not has_transient_or_ambiguous_evidence
    qualify row_number() over (
        partition by message_id, email
        order by sent_at desc
    ) = 1

),

-- Only addresses with bounce history are eligible for a recovery signal, which
-- is what keeps this model from asserting "valid" about every person we have
-- ever received mail from.
bounced_addresses as (

    select
        email,
        max(_ingested_at) as last_failure_ingested_at
    from permanent_failures
    group by email

),

recoveries as (

    select
        {{ nexus.create_nexus_id('event', ['p.message_id']) }} as event_id,
        p.message_id,
        p.email,
        p.sent_at,
        -- `_ingested_at` is a pipeline watermark, not a business timestamp, and
        -- downstream unions filter incrementally on it. A recovery row only
        -- exists once BOTH the message and the bounce have landed, so it must
        -- advertise the later of the two or a recovery derived from an
        -- already-absorbed message would never re-offer itself.
        {% if target.type == 'bigquery' %}GREATEST{% else %}greatest{% endif %}(p._ingested_at, b.last_failure_ingested_at) as _ingested_at
    from {{ ref('gmail_message_participants') }} p
    inner join bounced_addresses b
        on p.email = b.email
    where p.role = 'sender'

),

traits as (

    -- Permanent failure: this address could not be reached.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'address_invalid'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'address_invalid' as trait_name,
        'true' as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- When that failure was reported.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'address_invalid_at'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'address_invalid_at' as trait_name,
        cast(sent_at as {{ dbt.type_string() }}) as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- Why, in the mail system's own words, with the enhanced status code in
    -- front when the snippet exposed one.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'address_invalid_reason'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'address_invalid_reason' as trait_name,
        TRIM(COALESCE(smtp_status || ' ', '') || SUBSTR(snippet, 1, 200)) as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- Recovery: a previously-bouncing address sent us mail, so the mailbox is
    -- live again. Wins only if it is more recent than the failure.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'address_invalid'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'address_invalid' as trait_name,
        'false' as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from recoveries

)

select
    entity_trait_id,
    event_id,
    entity_type,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    source,
    occurred_at,
    _ingested_at
from traits
where trait_value is not null
  and trait_value != ''
qualify row_number() over (
    partition by entity_trait_id
    order by occurred_at desc, _ingested_at desc
) = 1
