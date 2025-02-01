/**
 * Utilities for loading Java properties files.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022-2025 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.java;

import mirage.config : ConfigDictionary;
import mirage.keyvalue : KeyValueConfigFactory, SupportHashtagComments, SupportSemicolonComments,
    SupportExclamationComments, SupportSections, NormalizeQuotedValues, SupportEqualsSeparator,
    SupportColonSeparator, SupportKeysWithoutValues, SupportMultilineValues;

/** 
 * Creates configuration dictionaries from Java properties.
 *
 * Format specifications: 
 *   https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/Properties.html#load(java.io.Reader)
 *   https://en.wikipedia.org/wiki/.properties
 */
class JavaPropertiesFactory : KeyValueConfigFactory!(
    SupportHashtagComments.yes,
    SupportSemicolonComments.no,
    SupportExclamationComments.yes,
    SupportSections.no,
    NormalizeQuotedValues.no,
    SupportEqualsSeparator.yes,
    SupportColonSeparator.yes,
    SupportKeysWithoutValues.yes,
    SupportMultilineValues.yes
) {
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

/// ditto
alias parseJavaConfig = parseJavaProperties;

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

/// ditto
alias loadJavaConfig = loadJavaProperties;

version (unittest) {
    import std.exception : assertThrown;
    import std.process : environment;
    import mirage.config : ConfigCreationException;

    @("Parse java properties")
    unittest {
        auto config = parseJavaProperties("
            # I have a comment
            bla=one
            di.bla=two
            meh: very # except when meh=not very
            much = not much
            much: much !important!!!!!!!!
            empty
            multi = we are \\
                    two lines
        ");

        assert(config.get("bla") == "one");
        assert(config.get("di.bla") == "two");
        assert(config.get("meh") == "very");
        assert(config.get("much") == "much");
        assert(config.get("empty") == "");
        assert(config.get("multi") == "we are two lines");
    }

    @("Parse java properties file")
    unittest {
        auto config = loadJavaProperties("testfiles/java.properties");
        assert(config.get("bla") == "one");
        assert(config.get("di.bla") == "two");
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
        auto config = parseJavaConfig("
            one    =       money
        ");

        assert(config.get("one") == "money");
    }

    @("Quotes in values are preserved")
    unittest {
        auto config = parseJavaProperties("
            one=\"two\"
            three='four'
        ");

        assert(config.get("one") == "\"two\"");
        assert(config.get("three") == "'four'");
    }
}
