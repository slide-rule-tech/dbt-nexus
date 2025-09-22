{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if 'sources/' not in node.original_file_path -%}
        
        {%- if target.name == 'prod' -%}
            
            {%- if var('nexus_schema_prod', none) is not none -%}
                {{ var('nexus_schema_prod') | trim }}
            {%- elif custom_schema_name is none  -%}
                nexus_prod
            {%- else -%}
                {{ custom_schema_name | trim }}
            {%- endif -%}

        {%- else -%}

            {%- if var('nexus_schema_dev', none) is not none -%}
                {{ var('nexus_schema_dev') | trim }}
            {%- elif custom_schema_name is none  -%}
                nexus_{{ target.name }}
            {%- else -%}
                nexus_{{ target.name }}_{{ custom_schema_name | trim }}
            {%- endif -%}

        {%- endif -%}

    {%- else -%}

        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ default_schema }}_{{ custom_schema_name | trim }}
        {%- endif -%}

    {%- endif -%}

{%- endmacro %}
