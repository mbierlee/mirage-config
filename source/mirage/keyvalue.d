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
alias SupportExclamationComments = Flag!"SupportExclamationComments";
alias SupportSections = Flag!"SupportSections";
alias NormalizeQuotedValues = Flag!"NormalizeQuotedValues";
alias SupportEqualsSeparator = Flag!"SupportEqualsSeparator";
alias SupportColonSeparator = Flag!"SupportColonSeparator";
alias SupportKeysWithoutValues = Flag!"SupportKeysWithoutValues";
alias SupportMultilineValues = Flag!"SupportMultilineValues";

/** 
 * A generic reusable key/value config factory that can be configured to parse
 * the specifics of certain key/value formats.
 */
class KeyValueConfigFactory(
    SupportHashtagComments supportHashtagComments = SupportHashtagComments.no,
    SupportSemicolonComments supportSemicolonComments = SupportSemicolonComments.no,
    SupportExclamationComments supportExclamationComments = SupportExclamationComments.no,
    SupportSections supportSections = SupportSections.no,
    NormalizeQuotedValues normalizeQuotedValues = NormalizeQuotedValues.no,
    SupportEqualsSeparator supportEqualsSeparator = SupportEqualsSeparator.no,
    SupportColonSeparator supportColonSeparator = SupportColonSeparator.no,
    SupportKeysWithoutValues supportKeysWithoutValues = SupportKeysWithoutValues.no,
    SupportMultilineValues supportMultilineValues = SupportMultilineValues.no
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
        enforce!ConfigCreationException(supportEqualsSeparator || supportColonSeparator, "No key/value separator is supported. Factory must set one either SupportEqualsSeparator or SupportColonSeparator");

        auto lines = contents.lineSplitter().array;
        auto properties = new ConfigDictionary();
        auto section = "";
        string key = null;
        string valueBuffer = "";

        foreach (size_t index, string line; lines) {
            auto processedLine = line;

            void replaceComments(bool isTypeSupported, char commentToken) {
                if (isTypeSupported) {
                    auto commentPosition = processedLine.indexOf(commentToken);
                    if (commentPosition >= 0) {
                        processedLine = processedLine[0 .. commentPosition];
                    }
                }
            }

            replaceComments(supportHashtagComments, '#');
            replaceComments(supportSemicolonComments, ';');
            replaceComments(supportExclamationComments, '!');

            processedLine = processedLine.strip;

            if (supportSections &&
                key is null &&
                processedLine.startsWith('[') && processedLine.endsWith(']')) {
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

            string value;

            if (key is null) {
                char keyValueSplitter;
                if (supportEqualsSeparator && processedLine.indexOf('=') >= 0) {
                    keyValueSplitter = '=';
                } else if (supportColonSeparator && processedLine.indexOf(':') >= 0) {
                    keyValueSplitter = ':';
                }

                auto parts = processedLine.split(keyValueSplitter);

                enforce!ConfigCreationException(parts.length <= 2, "Line has too many equals signs and cannot be parsed (L" ~ index
                        .to!string ~ "): " ~ processedLine);
                enforce!ConfigCreationException(supportKeysWithoutValues || parts.length == 2, "Missing value assignment (L" ~ index
                        .to!string ~ "): " ~ processedLine);

                key = [section, parts[0].strip].join('.');
                value = supportKeysWithoutValues && parts.length == 1 ? "" : parts[1].strip;
            } else {
                value = processedLine;
            }

            if (supportMultilineValues && value.endsWith('\\')) {
                valueBuffer ~= value[0 .. $ - 1];
                continue;
            }

            auto fullValue = valueBuffer ~ value;
            if (normalizeQuotedValues &&
                fullValue.length > 1 &&
                (fullValue.startsWith('"') || fullValue.startsWith('\'')) &&
                (fullValue.endsWith('"') || fullValue.endsWith('\''))) {
                fullValue = fullValue[1 .. $ - 1];
            }

            properties.set(key, fullValue);
            key = null;
            valueBuffer = "";
        }

        return properties;
    }
}

version (unittest) {
    import std.exception : assertThrown;
    import std.process : environment;

    class TestKeyValueConfigFactory : KeyValueConfigFactory!(
        SupportHashtagComments.no,
        SupportSemicolonComments.no,
        SupportExclamationComments.no,
        SupportSections.no,
        NormalizeQuotedValues.no,
        SupportEqualsSeparator.yes,
        SupportColonSeparator.no,
        SupportKeysWithoutValues.no,
        SupportMultilineValues.no
    ) {
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
            SupportSemicolonComments.yes,
            SupportExclamationComments.yes,
            SupportSections.no,
            NormalizeQuotedValues.no,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no
        )().parseConfig("
            # this is a comment
            ; this is another comment
            ! this then is also a comment!
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

    @("Succeed to parse when value assignment is missing and SupportKeysWithoutValues = yes")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.no,
            SupportSemicolonComments.no,
            SupportExclamationComments.no,
            SupportSections.no,
            NormalizeQuotedValues.no,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no,
            SupportKeysWithoutValues.yes
        )().parseConfig("answertolife");

        assert(config.get("answertolife") == "");
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
            SupportSemicolonComments.yes,
            SupportExclamationComments.yes,
            SupportSections.no,
            NormalizeQuotedValues.no,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no
        )().parseConfig("
            server=localhost #todo: change me. default=localhost when not set.
            port=9876; I think this port = right?
            timeout=36000 ! pretty long!
        ");

        assert(config.get("server") == "localhost");
        assert(config.get("port") == "9876");
        assert(config.get("timeout") == "36000");
    }

    @("Support sections when enabled")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.no,
            SupportSemicolonComments.yes,
            SupportExclamationComments.no,
            SupportSections.yes,
            NormalizeQuotedValues.no,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no
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
            SupportExclamationComments.no,
            SupportSections.no,
            NormalizeQuotedValues.yes,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no
        )().parseConfig("
            baboon = \"ape\"
            monkey = 'ape'
            human = ape
            excessiveWhitespace = '             '
            breaksWithComments = '   # Don't do this    '
        ");

        assert(config.get("baboon") == "ape");
        assert(config.get("monkey") == "ape");
        assert(config.get("human") == "ape");
        assert(config.get("excessiveWhitespace") == "             ");
        assert(config.get("breaksWithComments") == "'");
    }

    @("Support colon as key/value separator")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.no,
            SupportSemicolonComments.no,
            SupportExclamationComments.no,
            SupportSections.no,
            NormalizeQuotedValues.no,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.yes
        )().parseConfig("
            one = here
            two: also here
        ");

        assert(config.get("one") == "here");
        assert(config.get("two") == "also here");

        assertThrown!ConfigCreationException(new KeyValueConfigFactory!()().parseConfig("a=b")); // No separator is configured
    }

    @("Support multiline values")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.yes,
            SupportSemicolonComments.no,
            SupportExclamationComments.no,
            SupportSections.yes,
            NormalizeQuotedValues.yes,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no,
            SupportKeysWithoutValues.yes,
            SupportMultilineValues.yes
        )().parseConfig("
            sentence = the quick \\
                       'brown fox' \\ # comments
                       [jump]\\
                \\
                       ed over \\ #are not part of the
                       the lazy \\
            '[dog]'   #value

            not part of the sentence
        ");

        assert(config.get("sentence") == "the quick 'brown fox' [jump]ed over the lazy '[dog]'");
    }

    @("Normalize multiline values with quotes")
    unittest {
        auto config = new KeyValueConfigFactory!(
            SupportHashtagComments.no,
            SupportSemicolonComments.no,
            SupportExclamationComments.no,
            SupportSections.no,
            NormalizeQuotedValues.yes,
            SupportEqualsSeparator.yes,
            SupportColonSeparator.no,
            SupportKeysWithoutValues.no,
            SupportMultilineValues.yes
        )().parseConfig("
            doubles = \"Well then there I was \\
                        doing my thing.\"
            singles = 'When suddenly \\
                a shark bit me \\
                            from the sky'
        ");

        assert(config.get("doubles") == "Well then there I was doing my thing.");
        assert(config.get("singles") == "When suddenly a shark bit me from the sky");
    }

}
