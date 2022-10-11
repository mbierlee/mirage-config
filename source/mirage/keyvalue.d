/**
 * Utilities for loading generic configuration files consisting of key/value pairs.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.keyvalue;

import mirage.config : ConfigFactory, ConfigDictionary, ConfigNode, ValueNode, ObjectNode, ConfigCreationException;

import std.string : lineSplitter, strip, startsWith, split, indexOf;
import std.array : array;
import std.exception : enforce;
import std.conv : to;
import std.typecons : Flag;

alias SupportHashtagComments = Flag!"supportHashtagComment";
alias SupportSemicolonComments = Flag!"supportSemicolonComments";

/** 
 * A generic reusable key/value config factory that can be configured to parse
 * the specifics of certain key/value formats.
 */
class KeyValueConfigFactory(
    SupportHashtagComments supportHashtagComments = SupportHashtagComments.no,
    SupportSemicolonComments supportSemicolonComments = SupportSemicolonComments.no
) : ConfigFactory {
    /**
     * Parse a configuration file following the configured key/value conventions.
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
            auto normalizedLine = line;

            if (supportHashtagComments) {
                auto commentPosition = normalizedLine.indexOf('#');
                if (commentPosition >= 0) {
                    normalizedLine = normalizedLine[0 .. commentPosition];
                }
            }

            if (supportSemicolonComments) {
                auto commentPosition = normalizedLine.indexOf(';');
                if (commentPosition >= 0) {
                    normalizedLine = normalizedLine[0 .. commentPosition];
                }
            }

            normalizedLine = normalizedLine.strip;
            if (normalizedLine.length == 0) {
                continue;
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

version (unittest) {
    import std.exception : assertThrown;
    import std.process : environment;

    class TestKeyValueConfigFactory : KeyValueConfigFactory!() {
    }

    @("Parse standard key/value config")
    unittest {
        auto config = new TestKeyValueConfigFactory().parseConfig("
            bla=one
            di.bla=two
        ");

        assert(config.get("bla") == "one");
        assert(config.get("di.bla") == "two");
    }

    @("Parse and ignore comments")
    unittest {
        auto config = new KeyValueConfigFactory!(SupportHashtagComments.yes,
            SupportSemicolonComments.yes
        )().parseConfig("
            # this is a comment
            ; this is another comment
            iamset=true
        ");

        assert(config.get!bool("iamset"));
    }

    @("Fail to parse when there are too many equals signs")
    unittest {
        assertThrown!ConfigCreationException(new TestKeyValueConfigFactory()
                .parseConfig("one=two=three"));
    }

    @("Fail to parse when value assignment is missing")
    unittest {
        assertThrown!ConfigCreationException(new TestKeyValueConfigFactory()
                .parseConfig(
                    "answertolife"));
    }

    @("Substitute env vars")
    unittest {
        environment["MIRAGE_TEST_ENVY"] = "Much";
        auto config = new TestKeyValueConfigFactory().parseConfig("envy=$MIRAGE_TEST_ENVY");

        assert(config.get("envy") == "Much");
    }

    @("Use value from other key")
    unittest {
        auto config = new TestKeyValueConfigFactory().parseConfig("
            one=money
            two=${one}
        ");

        assert(config.get("two") == "money");
    }

    @("Values and keys are trimmed")
    unittest {
        auto config = new TestKeyValueConfigFactory().parseConfig("
            one    =       money
        ");

        assert(config.get("one") == "money");
    }

    @("Remove end-of-line comments")
    unittest {
        auto config = new KeyValueConfigFactory!(SupportHashtagComments.yes,
            SupportSemicolonComments.yes)().parseConfig("
            server=localhost #todo: change me. default=localhost when not set.
            port=9876; I think this port = right?
        ");

        assert(config.get("server") == "localhost");
        assert(config.get("port") == "9876");
    }
}
