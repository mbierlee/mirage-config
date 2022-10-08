module examples.manipulation.app;

/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

import mirage.config : loadConfig;

import std.stdio : writeln;

void main() {
    auto config = loadConfig("config.json");
    config.set("application.name", "Real HTTP Server");

    auto applicationName = config.get("application.name");
    writeln(applicationName);
}
