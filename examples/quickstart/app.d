module examples.quickstart.app;

/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022-2023 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

import std.stdio : writeln;
import mirage : loadConfig, parseIniConfig;

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
