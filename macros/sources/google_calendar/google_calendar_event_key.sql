{# Google Calendar instance identity — the single definition of the key.

    Three models need the same key and MUST agree: the base dedup view, the
    normalized event model, and the participants model. When they disagree the
    participant -> event join silently loses every edge (participants carry the
    raw key, events carry its hash, and nothing tests the join), so the
    expression lives here rather than being copy-pasted three times.
#}

{# instance_start: the occurrence this row describes.

    originalStartTime wins for a recurring instance -- it names the slot the
    instance belongs to, which survives the instance being dragged to a new
    time. Falls back to the event's own start, then to an all-day date.

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


{# is_recurring: does this row describe one occurrence of a series?

    Gates the event_key branch below, so getting it wrong silently collapses a
    whole series onto one key.

    The obvious tests -- recurringEventId, or a recurrence array on the master
    -- are NOT sufficient. Google omits recurringEventId from some payloads,
    notably bulk cancellations of a series' future instances: hundreds of rows
    arrive carrying distinct instance ids and start times but no recurrence
    metadata at all. Trusting those two fields alone makes every one of them
    look like the same single event.

    The instance id itself is the dependable signal. Google mints a recurring
    instance's id as <masterId>_<YYYYMMDDTHHMMSSZ>, and that suffix is present
    whatever else the payload omits. Single-event ids are opaque hex/base32 and
    never carry it.
#}
{% macro google_calendar_is_recurring(raw_record='_raw_record') %}
(
    JSON_EXTRACT_SCALAR({{ raw_record }}, '$.recurringEventId') IS NOT NULL
    OR (
        JSON_EXTRACT_ARRAY({{ raw_record }}, '$.recurrence') IS NOT NULL
        AND ARRAY_LENGTH(JSON_EXTRACT_ARRAY({{ raw_record }}, '$.recurrence')) > 0
    )
    OR {% if target.type == 'bigquery' -%}
    REGEXP_CONTAINS(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.id'), r'_[0-9]{8}T[0-9]{6}Z$')
    {%- else -%}
    regexp_matches(JSON_EXTRACT_SCALAR({{ raw_record }}, '$.id'), '_[0-9]{8}T[0-9]{6}Z$')
    {%- endif %}
)
{% endmacro %}


{# normalized_ical_uid: iCalUID with the recurrence-split suffix stripped.

    Editing a recurring series with "this and following" makes Google re-cut
    the series: it issues a NEW iCalUID of the form

        <master>_R<YYYYMMDDTHHMMSSZ>@google.com

    while the instance's own `id` stays put. The same real occurrence therefore
    accumulates two or three iCalUIDs over its lifetime, and keying on the raw
    value splits one meeting into several rows that disagree about `status` --
    the old series' future instances go `cancelled` when the series is re-cut,
    the new series' copies stay `confirmed`.

    Stripping the _R suffix collapses every variant back onto the base master,
    which restores the invariant the key depends on: one occurrence, one key.

    We normalize rather than switching to Google's `id` because iCalUID is also
    what dedups the same meeting across calendars/accounts (like Message-ID for
    Gmail). An occurrence that appears on more than one synced calendar has a
    different `id` per copy but one shared uid, so keying on `id` would trade
    this bug for the mirror-image one.

    Character class is [0-9] rather than \d: the pattern travels through Jinja
    to both BigQuery and duckdb, and avoiding the backslash avoids an escaping
    hazard in every hop.
#}
{% macro google_calendar_normalized_ical_uid(ical_uid='ical_uid') %}
{%- if target.type == 'bigquery' -%}
REGEXP_REPLACE({{ ical_uid }}, r'_R[0-9]{8}T[0-9]{6}Z?@', '@')
{%- else -%}
regexp_replace({{ ical_uid }}, '_R[0-9]{8}T[0-9]{6}Z?@', '@')
{%- endif -%}
{% endmacro %}


{# event_key: the normalized uid, plus the occurrence it names when recurring.

    The instance_start half applies to RECURRING EVENTS ONLY, and the
    distinction is load-bearing in both directions:

    - A recurring instance needs it, because one uid covers every occurrence in
      the series. originalStartTime names the slot and survives the instance
      being dragged to a new time, so the key is stable under rescheduling.

    - A single event must NOT have it. There is no originalStartTime to fall
      back on, so instance_start is just the event's current start -- and
      rescheduling a one-off meeting would mint a brand new key, leaving the
      old start sitting in the warehouse as a phantom second occurrence.

    Callers must already have filtered iCalUID IS NOT NULL. Rows without a uid
    also have no start at all (they are the stripped deletion tombstones), so
    that one guard covers both halves of the key.
#}
{% macro google_calendar_event_key(ical_uid='ical_uid', instance_start='instance_start', is_recurring='is_recurring') %}
CASE
    WHEN {{ is_recurring }} THEN CONCAT(
        {{ nexus.google_calendar_normalized_ical_uid(ical_uid) }},
        '|',
        CAST({{ instance_start }} AS {% if target.type == 'bigquery' %}STRING{% else %}VARCHAR{% endif %})
    )
    ELSE {{ nexus.google_calendar_normalized_ical_uid(ical_uid) }}
END
{% endmacro %}
