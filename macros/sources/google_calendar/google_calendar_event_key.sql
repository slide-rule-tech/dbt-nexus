{# Google Calendar occurrence attributes.

    NOTE ON IDENTITY: there is deliberately no key macro here. The occurrence
    key is Google's own `id`, used verbatim.

    This replaced an iCalUID-derived composite key. That key existed on the
    reasoning that iCalUID is to Calendar what Message-ID is to Gmail — the
    thing that recognises one record across several mailboxes. The analogy does
    not hold. Gmail mints a distinct per-mailbox message id, so Message-ID is
    genuinely required; Google Calendar propagates ONE event id to every
    attendee's copy within a tenant. Verified against a multi-calendar tenant:
    of the occurrences appearing on more than one synced calendar, all but a
    handful carried an identical `id`. The problem the composite key solved is
    almost entirely absent.

    What the composite key did cost was a branch — recurring occurrences keyed
    on uid+instance_start, single ones on uid alone — and every payload that
    made that branch guess wrong collapsed a whole series onto one row. Using
    `id` removes the branch, and with it that class of bug.

    `id` is also stable under exactly the mutations that matter: rescheduling a
    single event, dragging a recurring instance (the id encodes the ORIGINAL
    slot), and re-cutting a series with "this and following" (the id keeps the
    base master while iCalUID and recurringEventId are both reissued).
#}

{# instance_start: the occurrence this row describes.

    originalStartTime wins for a recurring instance -- it names the slot the
    instance belongs to, and survives the instance being dragged elsewhere.
    Falls back to the event's own start, then to an all-day date.

    ISO 8601 with fractional seconds + tz offset. BQ needs PARSE_TIMESTAMP with
    %E*S/%Ez format codes (duck strptime doesn't recognize). try_cast on both
    adapters auto-detects ISO 8601 and is equivalent for this format.
#}
{% macro google_calendar_instance_start(raw_record='_raw_record') %}
{%- if target.type == 'bigquery' -%}
SAFE_CAST(COALESCE(
    JSON_EXTRACT_SCALAR({{ raw_record }}, '$.originalStartTime.dateTime'),
    JSON_EXTRACT_SCALAR({{ raw_record }}, '$.start.dateTime'),
    CONCAT(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.start.date'), 'T00:00:00Z')
) AS TIMESTAMP)
{%- else -%}
try_cast(COALESCE(
    JSON_EXTRACT_SCALAR({{ raw_record }}, '$.originalStartTime.dateTime'),
    JSON_EXTRACT_SCALAR({{ raw_record }}, '$.start.dateTime'),
    CONCAT(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.start.date'), 'T00:00:00Z')
) AS TIMESTAMP)
{%- endif -%}
{% endmacro %}


{# series_id: which recurring series this occurrence belongs to, or NULL.

    Read off the instance id, which Google mints as

        <masterId>_<YYYYMMDDTHHMMSSZ>   timed occurrence
        <masterId>_<YYYYMMDD>           all-day occurrence

    Both suffix shapes must be matched. Handling only the timed one is the bug
    this rewrite fixes: all-day series fell through and collapsed.

    Preferred over recurringEventId for two reasons. It is present even on the
    stripped payloads Google sends for bulk cancellations, where
    recurringEventId is omitted. And it is stable across series re-cuts, where
    recurringEventId is reissued as <masterId>_R<timestamp> — verified against
    live data: wherever the two differ, they differ by exactly that _R suffix
    and never otherwise. So series_id identifies the series; recurring_event_id
    (kept as its own column) identifies which cut of it.
#}
{% macro google_calendar_series_id(raw_record='_raw_record') %}
{%- if target.type == 'bigquery' -%}
REGEXP_EXTRACT(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.id'), r'^(.+)_[0-9]{8}(?:T[0-9]{6}Z)?$')
{%- else -%}
regexp_extract(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.id'), '^(.+)_[0-9]{8}(T[0-9]{6}Z)?$', 1)
{%- endif -%}
{% endmacro %}


{# is_recurring: purely descriptive now — nothing keys off it.

    A miss here is a wrong label on one row, not a collapsed series, which is
    why this can be a simple OR rather than the load-bearing branch it was.

    No recurrence[] test: the sync expands instances (singleEvents), so a
    series master with a recurrence array is never landed. That arm of the old
    condition was dead code.
#}
{% macro google_calendar_is_recurring(raw_record='_raw_record') %}
(
    {{ nexus.google_calendar_series_id(raw_record) }} IS NOT NULL
    OR JSON_EXTRACT_SCALAR({{ raw_record }}, '$.recurringEventId') IS NOT NULL
)
{% endmacro %}
