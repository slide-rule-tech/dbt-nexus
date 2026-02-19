{% macro get_entity_type_config() %}
  {# Returns a dict of { entity_type_name: { entity_resolution: bool, ... } }
     Handles both new dict format and legacy list format for backward compatibility.

     New format (dbt_project.yml):
       nexus:
         entity_types:
           person:
             entity_resolution: true
           subscription:
             entity_resolution: false

     Legacy format:
       nexus:
         entity_types: ["person", "group"]
       -- or --
       nexus_entity_types: ["person", "group"]
  #}
  {% set raw = var('nexus', {}).get('entity_types') or var('nexus_entity_types', ['person', 'group']) %}

  {% if raw is mapping %}
    {% do return(raw) %}
  {% else %}
    {% set config = {} %}
    {% for entity_type in raw %}
      {% do config.update({entity_type: {'entity_resolution': true}}) %}
    {% endfor %}
    {% do return(config) %}
  {% endif %}
{% endmacro %}


{% macro get_all_entity_types() %}
  {# Returns a list of all entity type names (both ER and non-ER). #}
  {% set config = nexus.get_entity_type_config() %}
  {% do return(config.keys() | list) %}
{% endmacro %}


{% macro get_er_entity_types() %}
  {# Returns a list of entity type names that require entity resolution. #}
  {% set config = nexus.get_entity_type_config() %}
  {% set er_types = [] %}
  {% for entity_type, type_config in config.items() %}
    {% if type_config.get('entity_resolution', true) %}
      {% do er_types.append(entity_type) %}
    {% endif %}
  {% endfor %}
  {% do return(er_types) %}
{% endmacro %}


{% macro get_non_er_entity_types() %}
  {# Returns a list of entity type names that skip entity resolution. #}
  {% set config = nexus.get_entity_type_config() %}
  {% set non_er_types = [] %}
  {% for entity_type, type_config in config.items() %}
    {% if not type_config.get('entity_resolution', true) %}
      {% do non_er_types.append(entity_type) %}
    {% endif %}
  {% endfor %}
  {% do return(non_er_types) %}
{% endmacro %}


{% macro is_er_entity_type(entity_type) %}
  {# Returns true if the given entity type requires entity resolution. #}
  {% set config = nexus.get_entity_type_config() %}
  {% set type_config = config.get(entity_type, {}) %}
  {% do return(type_config.get('entity_resolution', true)) %}
{% endmacro %}
