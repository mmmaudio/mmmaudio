*For more information about the examples, such as how the Python and Mojo files interact with each other, see the [Examples Overview](index.md)*

# {{ example_name }}

<!-- Use mkdocs ":::" syntax to get docstring from Python file -->
:::{{example_module}}
    options:
      members: []

{% if tosc is defined %}
This example has a corresponding [TouchOSC file](https://github.com/spluta/MMMAudio/blob/main/{{ example_rel_dir }}/{{ tosc }}).
{% endif %}

## Python Code
<!-- Puts the remaining lines from the Python script here -->
```python

{{code}}

```

## Mojo Code
<!-- Put the contents of the .mojo file *of the same name!* here -->
```mojo

--8<-- "{{ example_rel_dir }}/{{mojo_file_name}}"

```