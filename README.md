# Mirage Config

Version 1.0.0  
Copyright 2022 Mike Bierlee  
Licensed under the terms of the MIT license - See [LICENSE.txt](LICENSE.txt)

[![DUB Package](https://img.shields.io/dub/v/mirage-config.svg)](https://code.dlang.org/packages/mirage-config) 

Toolkit for loading and using application configuration from various formats.

Features:

- Load from various file formats such as JSON, INI and Java properties (see [Formats](#formats));
- Environment variable substitution;
- Internal configuration substitution (Value in config replaced by other path in config);
- Parse configuration from string or JSONValue instead of from disk.

## Getting started
### DUB Dependency
See the [DUB project page](https://code.dlang.org/packages/mirage-config) for instructions on how to include Mirage Config into your project.

### Quickstart
```d
import std.stdio : writeln;
import mirage : loadConfig, parseJavaProperties;

void main() {
    // Load configuration from file (see examples/quickstart/config.json)
    auto config = loadConfig("config.json");
    writeln(config.get("application.name"));
    writeln(config.get!long("application.version"));

    // Or parse directly from string
    auto ini = parseIniConfig("
        databaseDriver = Postgres

        [database]
        host = localhost
        port = 5432
    ");

    auto databaseConfig = ini.getConfig("database");

    writeln(ini.get("databaseDriver"));
    writeln(databaseConfig.get("host"));
    writeln(databaseConfig.get("port"));
}
```

More formats are available (see [Formats](#formats).)  
For more details and examples, see the [examples](examples) directory.

## Formats
The following file formats are currently supported:

| Format      | Extension   | Import<sup>*</sup> | Loader                    | Parser                          | Factory                 |
|-------------|-------------|--------------------|---------------------------|---------------------------------|-------------------------|
| _any below_ | _any below_ | `mirage`           | `loadConfig`<sup>**</sup> | _(N/A)_                         |                         |
| INI         | .ini        | `mirage.ini`       | `loadIniConfig`           | `parseIniConfig`                | `IniConfigFactory`      |
| Java        | .properties | `mirage.java`      | `loadJavaProperties`      | `parseJavaProperties`           | `JavaPropertiesFactory` |
| JSON        | .json       | `mirage.json`      | `loadJsonConfig`          | `parseJsonConfig`<sup>***</sup> | `JsonConfigFactory`     |

<sup>\*</sup> _Any loader or parser can be imported from the `mirage` package since they are all publicly imported._  
<sup>\*\*</sup> _Loads files based on their extension. If the file does not use one of the extensions in the table, you must use a specific loader._  
<sup>\*\*\*</sup> _Besides parsing strings like the other formats, it also accepts a `JSONValue`._

Documentation
-------------
You can generate documentation from the source code using DUB:
```
dub build --build=ddox
```
The documentation can then be found in docs/

## History

For a full overview of changes, see [CHANGES.md](CHANGES.md)

## Contributing

Any and all pull requests are welcome! If you (only) want discuss changes before making them, feel free to open an Issue on github. Please develop your changes on (a branch based on) the develop branch. Continuous integration is preferred so feature branches are not neccessary.