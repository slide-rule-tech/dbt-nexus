{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'person_traits', 'bounces']
) }}

{#-
  `email_address_invalid` traits for the FAILED RECIPIENT of a delivery status
  notification (DSN).

  All the parsing lives upstream in the normalized layer:
    - gmail_messages carries `is_bounce_notification` (the message has an
      `X-Failed-Recipients` header), `is_permanent_bounce` (snippet
      classification — see macros/helpers/gmail_bounce_classification.sql)
      and `bounce_smtp_status`.
    - gmail_message_participants carries the bounced address as a participant
      with role 'failed_recipient', parsed from that header.
  This model only joins the two and emits traits.

  TWO TRAIT FAMILIES. `is_email_deliverable` is the STANDARD, source-agnostic
  verdict — "can we send to this address?" — and any source that detects
  bounces (Gmail DSNs here; an ESP's bounce webhooks, Exchange NDRs, … later)
  emits the same trait name so downstream reads one column regardless of who
  saw the bounce. `email_address_invalid` / `_at` / `_reason` are this source's
  evidence for that verdict and stay for auditability.

  SEMANTICS — a VERDICT, NOT A TOMBSTONE. `nexus_resolved_entity_traits` keeps
  the latest value per (entity, trait_name) ordered by `occurred_at`, so the
  newest signal wins — across sources too. Two signals are emitted:

    permanent bounce   is_email_deliverable = 'false', email_address_invalid = 'true'
                       at the DSN's send time.
    recovery           is_email_deliverable = 'true',  email_address_invalid = 'false'
                       at the send time of any message the bounced address
                       itself SENT us. Receiving mail from an address is
                       positive evidence the mailbox is live, so a restored
                       mailbox clears itself on the next inbound message with
                       no manual step.

  Ordering by `occurred_at` does the work: inbound mail from BEFORE the bounce
  loses to it, inbound mail from after it wins. Recovery rows are only emitted
  for addresses that have actually bounced, so downstream reads three states
  of is_email_deliverable: NULL = no evidence either way (fine to send),
  'false' = exclude, 'true' = bounced once but has written since.

  `email_address_invalid_at` / `email_address_invalid_reason` are emitted ONLY on failure
  rows and are left standing after a recovery so the history stays auditable.
  The reason carries the enhanced status code when the snippet exposed one plus
  the snippet verbatim — the raw sentence is what a human needs to second-guess
  the classification, and it cannot drift out of sync with a regex.

  MATERIALIZED AS A TABLE, not incrementally: the recovery leg needs full
  history (a bounce landing today must find inbound mail from that address
  ingested years ago), which an `_ingested_at` watermark would hide. Permanent
  bounces are rare (tens of rows), so the cost is one scan per run.
-#}

with permanent_failures as (

    select
        {{ nexus.create_nexus_id('event', ['p.message_id']) }} as event_id,
        p.message_id,
        p.email,
        p.sent_at,
        m.bounce_smtp_status,
        m.snippet,
        {% if target.type == 'bigquery' %}GREATEST{% else %}greatest{% endif %}(p._ingested_at, m._ingested_at) as _ingested_at
    from {{ ref('gmail_message_participants') }} p
    inner join {{ ref('gmail_messages') }} m
        on p.message_id = m.message_id
    where p.role = 'failed_recipient'
      and m.is_permanent_bounce

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

    -- STANDARD trait: not deliverable. Same name every bounce source emits.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'is_email_deliverable'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'is_email_deliverable' as trait_name,
        'false' as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- STANDARD trait: deliverable again — the address wrote to us after bouncing.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'is_email_deliverable'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'is_email_deliverable' as trait_name,
        'true' as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from recoveries

    union all

    -- Source evidence: this address could not be reached (Gmail DSN).
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'email_address_invalid'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email_address_invalid' as trait_name,
        'true' as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- When that failure was reported.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'email_address_invalid_at'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email_address_invalid_at' as trait_name,
        cast(sent_at as {{ dbt.type_string() }}) as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- Why, in the mail system's own words, with the enhanced status code in
    -- front when the snippet exposed one.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'email_address_invalid_reason'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email_address_invalid_reason' as trait_name,
        TRIM(COALESCE(bounce_smtp_status || ' ', '') || SUBSTR(snippet, 1, 200)) as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    from permanent_failures

    union all

    -- Recovery: a previously-bouncing address sent us mail, so the mailbox is
    -- live again. Wins only if it is more recent than the failure.
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'email_address_invalid'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email_address_invalid' as trait_name,
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
