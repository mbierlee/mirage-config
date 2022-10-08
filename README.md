# Mirage Config

Version 0.0.0  
Copyright 2022 Mike Bierlee  
Licensed under the terms of the MIT license - See [LICENSE.txt](LICENSE.txt)

Toolkit for loading and using application configuration from various formats.

Features:

- Load from various file formats such as JSON and Java properties (see [Formats](#formats));
- Environment variable substitution;
- Internal configuration substitution (Value in config replaced by other path in config);
- Parse configuration from string or JSONValue instead of from disk.

TODO: add tutorial on:

- Config loading
- Config parsing
- Config manip
- Env and config var substitution
  -- Escaping

## Getting started
### DUB Dependency
See the [DUB project page](https://code.dlang.org/packages/mirage-config) for instructions on how to include Mirage Config into your project.

### Quickstart
```d
import std.stdio : writeln;
import mirage : loadConfig, parseJavaProperties;

void main() {
    // Load configuration from file (see examples/quickstart/config.json):
    auto config = loadConfig("config.json");
    writeln(config.get("application.name"));
    writeln(config.get!long("application.version"));

    // Or parse directly from string:
    auto properties = parseJavaProperties("
        databaseDriver = Postgres
        database.host = localhost
        database.port = 5432
    ");

    auto databaseConfig = properties.getConfig("database");

    writeln(properties.get("databaseDriver"));
    writeln(databaseConfig.get("host"));
    writeln(databaseConfig.get("port"));
}
```

More formats are available (see [Formats](#formats)).  
For more details and examples, see the [examples](examples) directory.

## Formats
The following file formats are currently supported:

| Format      | Extension   | Import<sup>*</sup> | Loader                    | Parser                          | Factory                 |
|-------------|-------------|--------------------|---------------------------|---------------------------------|-------------------------|
| _any below_ | _any below_ | `mirage`           | `loadConfig`<sup>**</sup> | _(N/A)_                         |                         |
| JSON        | .json       | `mirage.json`      | `loadJsonConfig`          | `parseJsonConfig`<sup>***</sup> | `JsonConfigFactory`     |
| Java        | .properties | `mirage.java`      | `loadJavaProperties`      | `parseJavaProperties`           | `JavaPropertiesFactory` |

<sup>\*</sup> _Any loader or parser can be imported from the `mirage` package since they are all publicly imported._  
<sup>\*\*</sup> _Loads files based on their extension. If the file does not use one of the extensions in the table, you must use a specific loader._  
<sup>\*\*\*</sup> _Besides parsing strings like the other formats, it also accepts a `JSONValue`._

## History

For a full overview of changes, see [CHANGES.md](CHANGES.md)
