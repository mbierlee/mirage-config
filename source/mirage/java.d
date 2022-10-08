/**
 * Utilities for loading Java properties files.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.java;

import mirage.config : ConfigFactory, ConfigDictionary, ConfigNode, ValueNode, ObjectNode, ConfigCreationException;

import std.string : lineSplitter, strip, startsWith, split, indexOf;
import std.array : array;
import std.exception : enforce;
import std.conv : to;

/** 
 * Creates configuration files from Java properties.
 */
class JavaPropertiesFactory : ConfigFactory {
    /**
     * Parse configuration from the given Java properties string.
     *
     * Params:
     *   contents = Text contents of the config to be parsed.
     * Returns: The parsed configuration.
     */
    override ConfigDictionary parseConfig(string contents) {
        enforce!ConfigCreationException(contents !is null, "Contents cannot be null.");
        auto lines = contents.lineSplitter().array;
        auto properties = new ConfigDictionary();
        foreach (size_t index, string line; lines) {
            auto normalizedLine = line.strip;
            if (normalizedLine.length == 0 || normalizedLine.startsWith('#')) {
                continue;
            }

            auto commentPosition = normalizedLine.indexOf('#');
            if (commentPosition >= 0) {
                normalizedLine = normalizedLine[0 .. commentPosition];
            }

            auto parts = normalizedLine.split('=');
            enforce!ConfigCreationException(parts.length <= 2, "Line has too many equals signs and cannot be parsed (L" ~ index
                    .to!string ~ "): " ~ normalizedLine);
            enforce!ConfigCreationException(parts.length == 2, "Missing value assignment (L" ~ index.to!string ~ "): " ~ normalizedLine);
            properties.set(parts[0].strip, parts[1].strip);
        }

        return properties;
    }
}

/** 
 * Parse Java properties from the given Java properties string.

 * Params:
 *   properties = Text contents of the config to be parsed.
 * Returns: The parsed configuration.
 */
ConfigDictionary parseJavaProperties(const string properties) {
    return new JavaPropertiesFactory().parseConfig(properties);
}

/** 
 * Load a Java properties file from disk.
 *
 * Params:
 *   filePath = Path to the Java properties file.
 * Returns: The loaded configuration.
 */
ConfigDictionary loadJavaProperties(const string filePath) {
    return new JavaPropertiesFactory().loadFile(filePath);
}

version (unittest) {
    import std.exception : assertThrown;
    import std.process : environment;

    @("Parse java properties")
    unittest {
        auto config = parseJavaProperties("
            # I have a comment
            bla=one
            di.bla=two
        ");

        assert(config.get("bla") == "one");
        assert(config.get("di.bla") == "two");
    }

    @("Parse java properties file")
    unittest {
        auto config = loadJavaProperties("testfiles/java.properties");
        assert(config.get("bla") == "one");
        assert(config.get("di.bla") == "two");
    }

    @("Fail to parse when there are too many equals signs")
    unittest {
        assertThrown!ConfigCreationException(parseJavaProperties("one=two=three"));
    }

    @("Fail to parse when value assignment is missing")
    unittest {
        assertThrown!ConfigCreationException(parseJavaProperties("answertolife"));
    }

    @("Substitute env vars")
    unittest {
        environment["MIRAGE_TEST_ENVY"] = "Much";
        auto config = parseJavaProperties("envy=$MIRAGE_TEST_ENVY");

        assert(config.get("envy") == "Much");
    }

    @("Use value from other key")
    unittest {
        auto config = parseJavaProperties("
            one=money
            two=${one}
        ");

        assert(config.get("two") == "money");
    }

    @("Values and keys are trimmed")
    unittest {
        auto config = parseJavaProperties("
            one    =       money
        ");

        assert(config.get("one") == "money");
    }

    @("Remove end-of-line comments")
    unittest {
        auto config = parseJavaProperties("
            server=localhost #todo: change me. default=localhost when not set.
        ");

        assert(config.get("server") == "localhost");
    }
}
