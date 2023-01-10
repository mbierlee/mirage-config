/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022-2023 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

import mirage.config : loadConfig;

import std.stdio : writeln;
import std.process : environment;

void main() {
    // This example shows how values in configuration can be substituted with
    // environment variables or other configuration paths.

    environment["CONFIG_EXAMPLE_SUBJECT"] = "world";
    auto config = loadConfig("config.json"); // Can be done with other formats too.

    writeln(config.get("start")); // "Hello world! Enjoy your day!"
    writeln(config.get("end"));   // "Bye!"
}
