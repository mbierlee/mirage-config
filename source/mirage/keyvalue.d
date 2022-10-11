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

import std.string : lineSplitter, strip, startsWith, endsWith, split, indexOf, join;
import std.array : array;
import std.exception : enforce;
import std.conv : to;
import std.typecons : Flag;

alias SupportHashtagComments = Flag!"SupportHashtagComments";
alias SupportSemicolonComments = Flag!"SupportSemicolonComments";
alias SupportSections = Flag!"SupportSections";
alias NormalizeQuotedValues = Flag!"NormalizeQuotedValues";

/** 
 * A generic reusable key/value config factory that can be configured to parse
 * the specifics of certain key/value formats.
 */
class KeyValueConfigFactory(
    SupportHashtagComments supportHashtagComments = SupportHashtagComments.no,
    SupportSemicolonComments supportSemicolonComments = SupportSemicolonComments.no,
    SupportSections supportSections = SupportSections.no,
    NormalizeQuotedValues normalizeQuotedValues = NormalizeQuotedValues.no
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
        auto section = "";
        foreach (size_t index, string line; lines) {
            auto processedLine = line;

            if (supportHashtagComments) {
                auto commentPosition = processedLine.indexOf('#');
                if (commentPosition >= 0) {
                    processedLine = processedLine[0 .. commentPosition];
                }
            }

            if (supportSemicolonComments) {
                auto commentPosition = processedLine.indexOf(';');
                if (commentPosition >= 0) {
                    processedLine = processedLine[0 .. commentPosition];
                }
            }

            processedLine = processedLine.strip;

            if (supportSections && processedLine.startsWith('[') && processedLine.endsWith(']')) {
                auto parsedSection = processedLine[1 .. $ - 1];
                if (parsedSection.startsWith('.')) {
                    section ~= parsedSection;
                } else {
                    section = parsedSection;
                }

                continue;
            }

            if (processedLine.length == 0) {
                continue;
            }

            auto parts = processedLine.split('=');
            enforce!ConfigCreationException(parts.length <= 2, "Line has too many equals signs and cannot be parsed (L" ~ index
                    .to!string ~ "): " ~ processedLine);
            enforce!ConfigCreationException(parts.length == 2, "Missing value assignment (L" ~ index.to!string ~ "): " ~ processedLine);

            auto value = parts[1].strip;
            if (normalizeQuotedValues && (value.startsWith('"') || value.startsWith('\''))
                && (value.endsWith('"') || value.endsWith('\''))) {
                value = value[1 .. $ - 1];
            }

            auto key = [section, parts[0].strip].join('.');
            properties.set(key, value);
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
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.yes,
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
                .parseConfig("answertolife"));
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
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.yes,
            SupportSemicolonComments.yes
        )().parseConfig("
            server=localhost #todo: change me. default=localhost when not set.
            port=9876; I think this port = right?
        ");

        assert(config.get("server") == "localhost");
        assert(config.get("port") == "9876");
    }

    @("Support sections when enabled")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.no,
            SupportSemicolonComments.yes,
            SupportSections.yes
        )().parseConfig("
            applicationName = test me!

            [server]
            host=localhost
            port=2873

            [.toaster]
            color=chrome

            [server.middleware] ; Stuff that handles the http protocol
            protocolServer = netty

            [database.driver]
            id=PostgresDriver
        ");

        assert(config.get("applicationName") == "test me!");
        assert(config.get("server.host") == "localhost");
        assert(config.get("server.port") == "2873");
        assert(config.get("server.toaster.color") == "chrome");
        assert(config.get("server.middleware.protocolServer") == "netty");
        assert(config.get("database.driver.id") == "PostgresDriver");
    }

    @("Values with quotes are normalized and return the value within")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.yes,
            SupportSemicolonComments.no,
            SupportSections.no,
            NormalizeQuotedValues.yes
        )().parseConfig("
            baboon = \"ape\"
            monkey = 'ape'
            human = ape
            excessiveWhitespace = '             '
        ");

        assert(config.get("baboon") == "ape");
        assert(config.get("monkey") == "ape");
        assert(config.get("human") == "ape");
        assert(config.get("excessiveWhitespace") == "             ");
    }

}
