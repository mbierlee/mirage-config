/**
 * Utilities for loading INI files.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.ini;

import mirage.config : ConfigDictionary;
import mirage.keyvalue : KeyValueConfigFactory, SupportHashtagComments, SupportSemicolonComments,
    SupportExclamationComments, SupportSections, NormalizeQuotedValues, SupportEqualsSeparator,
    SupportColonSeparator, SupportKeysWithoutValues, SupportMultilineValues;

/** 
 * Creates configuration dictionaries from INI files.
 *
 * Format specifications:
 *   https://en.wikipedia.org/wiki/INI_file#Format
 */
class IniConfigFactory : KeyValueConfigFactory!(
    SupportHashtagComments.yes,
    SupportSemicolonComments.yes,
    SupportExclamationComments.no,
    SupportSections.yes,
    NormalizeQuotedValues.yes,
    SupportEqualsSeparator.yes,
    SupportColonSeparator.yes,
    SupportKeysWithoutValues.no,
    SupportMultilineValues.yes
) {
}

/** 
 * Parse configuration from the given INI config string.

 * Params:
 *   contents = Text contents of the config to be parsed.
 * Returns: The parsed configuration.
 */
ConfigDictionary parseIniConfig(const string contents) {
    return new IniConfigFactory().parseConfig(contents);
}

/** 
 * Load a INI configuration file from disk.
 *
 * Params:
 *   filePath = Path to the INI configuration file.
 * Returns: The loaded configuration.
 */
ConfigDictionary loadIniConfig(const string filePath) {
    return new IniConfigFactory().loadFile(filePath);
}

version (unittest) {
    import std.process : environment;

    @("Parse INI config")
    unittest {
        auto config = parseIniConfig("
            globalSection = yes

            [supersection]
            thefirst = here

            [supersection.sub]
            sandwich=maybe tasty

            [.way]
            advertisement? = nah ; For real, not sponsored!

            # Although money would be cool
            [back]
            to: basics
            much = \"very much whitespace\"
            many = 'very many whitespace'
        ");

        assert(config.get("globalSection") == "yes");
        assert(config.get("supersection.thefirst") == "here");
        assert(config.get("supersection.sub.sandwich") == "maybe tasty");
        assert(config.get("supersection.sub.way.advertisement?") == "nah");
        assert(config.get("back.much") == "very much whitespace");
        assert(config.get("back.many") == "very many whitespace");
    }

    @("Load INI file")
    unittest {
        auto config = loadIniConfig("testfiles/fuzzy.ini");

        assert(config.get("globalSection") == "yes");
        assert(config.get("supersection.thefirst") == "here");
        assert(config.get("supersection.sub.sandwich") == "maybe tasty");
        assert(config.get("supersection.sub.way.advertisement?") == "nah");
        assert(config.get("back.much") == "very much whitespace");
        assert(config.get("back.many") == "very many whitespace");
    }

    @("Substitute env vars")
    unittest {
        environment["MIRAGE_TEST_INI_VAR"] = "I am ini";
        auto config = parseIniConfig("
            [app]
            startInfo = ${MIRAGE_TEST_INI_VAR}
        ");

        assert(config.get("app.startInfo") == "I am ini");
    }

    @("Use value from other key")
    unittest {
        auto config = parseIniConfig("
            [app]
            startInfo = \"Let's get started!\"

            [logger]
            startInfo = ${app.startInfo}
        ");

        assert(config.get("app.startInfo") == "Let's get started!");
        assert(config.get("logger.startInfo") == "Let's get started!");
    }
}
