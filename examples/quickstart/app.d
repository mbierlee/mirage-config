module examples.quickstart.app;

/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

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
