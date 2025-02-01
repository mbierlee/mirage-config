/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022-2025 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

import mirage.json : loadJsonConfig, parseJsonConfig;

import std.stdio : writeln;
import std.conv : to;

void main() {
    auto config = loadJsonConfig("config.json");
    auto serverConfig = config.getConfig("server");
    auto databaseConfig = parseJsonConfig("
        {
            \"host\": \"localhost\",
            \"port\": 5432
        }
    ");

    auto applicationName = config.get("application.name");

    auto httpHost = serverConfig.get("host");
    auto httpPort = serverConfig.get!uint("port");
    auto httpProtocol = serverConfig.get("protocol");

    auto dbHost = databaseConfig.get("host");
    auto dbPort = databaseConfig.get!uint("port");

    writeln("Starting " ~ applicationName ~ "...");
    writeln("Connecting to database at " ~ dbHost ~ ":" ~ dbPort.to!string ~ "...");
    writeln(
        "HTTP server now listening at " ~ httpProtocol ~ "://" ~ httpHost ~ ":" ~ httpPort
            .to!string);
}
