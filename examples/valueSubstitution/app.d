/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

import mirage.json : loadJsonConfig, parseJsonConfig;

import std.stdio : writeln;
import std.process : environment;

void main() {
    // This example shows how values in configuration can be substituted from
    // environment variables or other configuration paths.

    environment["subject"] = "world";
    auto config = loadJsonConfig("config.json");

    writeln(config.get("greeting"));
}
