/**
 * Base utilities for working with configurations.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022-2025 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.config;

import std.exception : enforce;
import std.string : split, startsWith, endsWith, join, lastIndexOf, strip, toLower;
import std.conv : to, ConvException;
import std.file : readText;
import std.path : extension;
import std.process : environment;
import std.typecons : Flag;

import mirage.json : loadJsonConfig;
import mirage.java : loadJavaProperties;
import mirage.ini : loadIniConfig;

/** 
 * Used by the ConfigDictionary when something goes wrong when reading configuration.
 */
class ConfigReadException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/** 
 * Used by ConfigDictionary when the supplied path does not exist.
 */
class ConfigPathNotFoundException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/** 
 * Used by ConfigFactory instances when loading or parsing configuration fails.
 */
class ConfigCreationException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/** 
 * Used by ConfigDictionary when there is something wrong with the path when calling ConfigDictionary.get()
 */
class PathParseException : Exception {
    this(string msg, string path, string file = __FILE__, size_t line = __LINE__) {
        string fullMsg = msg ~ " (Path: " ~ path ~ ")";
        super(fullMsg, file, line);
    }
}

/** 
 * The configuration tree is made up of specific types of ConfigNodes.
 * Used as generic type for ConfigFactory and ConfigDictionary.
 */
interface ConfigNode {
    string nodeType();
}

/** 
 * A configuration item that is any sort of primitive value (strings, numbers or null).
 */
class ValueNode : ConfigNode {
    string value;

    this() {
    }

    this(string value) {
        this.value = value;
    }

    string nodeType() {
        return "value";
    }
}

/** 
 * A configuration item that is an object. 
 * 
 * ObjectNodes contain a node dictionary that points to other ConfigNodes.
 */
class ObjectNode : ConfigNode {
    ConfigNode[string] children;

    this() {
    }

    this(ConfigNode[string] children) {
        this.children = children;
    }

    this(string[string] values) {
        foreach (key, value; values) {
            children[key] = new ValueNode(value);
        }
    }

    string nodeType() {
        return "object";
    }
}

/** 
 * A configuration item that is an array.
 *
 * Contains other ConfigNodes as children.
 */
class ArrayNode : ConfigNode {
    ConfigNode[] children;

    this() {
    }

    this(ConfigNode[] children...) {
        this.children = children;
    }

    this(string[] values...) {
        foreach (string value; values) {
            children ~= new ValueNode(value);
        }
    }

    string nodeType() {
        return "array";
    }
}

private interface PathSegment {
}

private class ArrayPathSegment : PathSegment {
    const size_t index;

    this(const size_t index) {
        this.index = index;
    }
}

private class PropertyPathSegment : PathSegment {
    const string propertyName;

    this(const string propertyName) {
        this.propertyName = propertyName;
    }
}

private class ConfigPath {
    private const string path;
    private string[] previousSegments;
    private string[] segments;

    this(const string path) {
        this.path = path;
        segmentAndNormalize(path);
    }

    private void segmentAndNormalize(string path) {
        foreach (segment; path.split(".")) {
            auto trimmedSegment = segment.strip;

            if (trimmedSegment.length <= 0) {
                continue;
            }

            if (trimmedSegment.endsWith("]") && !trimmedSegment.startsWith("[")) {
                auto openBracketPos = trimmedSegment.lastIndexOf("[");
                if (openBracketPos != -1) {
                    segments ~= trimmedSegment[0 .. openBracketPos];
                    segments ~= trimmedSegment[openBracketPos .. $];
                    continue;
                }
            }

            segments ~= trimmedSegment;
        }
    }

    PathSegment getNextSegment() {
        if (segments.length == 0) {
            return null;
        }

        PathSegment ret(PathSegment segment) {
            previousSegments ~= segments[0];
            segments = segments[1 .. $];
            return segment;
        }

        string segment = segments[0];

        if (segment.startsWith("[") && segment.endsWith("]")) {
            if (segment.length <= 2) {
                throw new PathParseException("Path has array accessor but no index specified", path);
            }

            auto indexString = segment[1 .. $ - 1];
            try {
                auto index = indexString.to!size_t;
                return ret(new ArrayPathSegment(index));
            } catch (ConvException e) {
                throw new PathParseException("Value '" ~ indexString ~ "' is not acceptable as an array index", path);
            }
        }

        return ret(new PropertyPathSegment(segment));
    }

    string getCurrentPath() {
        return previousSegments.join(".");
    }
}

/** 
 * Used in a ConfigDictionary to enable to disable environment variable substitution.
 */
alias SubstituteEnvironmentVariables = Flag!"SubstituteEnvironmentVariables";

/** 
 * Used in a ConfigDictionary to enable to disable config path substitution.
 */
alias SubstituteConfigVariables = Flag!"SubstituteConfigVariables";

/** 
 * A ConfigDictionary contains the configuration tree and facilities to get values from that tree.
 */
class ConfigDictionary {
    ConfigNode rootNode;
    SubstituteEnvironmentVariables substituteEnvironmentVariables = SubstituteEnvironmentVariables
        .yes;
    SubstituteConfigVariables substituteConfigVariables = SubstituteConfigVariables.yes;

    this(SubstituteEnvironmentVariables substituteEnvironmentVariables = SubstituteEnvironmentVariables
            .yes, SubstituteConfigVariables substituteConfigVariables = SubstituteConfigVariables
            .yes) {
        this.substituteEnvironmentVariables = substituteEnvironmentVariables;
        this.substituteConfigVariables = substituteConfigVariables;
    }

    this(ConfigNode rootNode, SubstituteEnvironmentVariables substituteEnvironmentVariables = SubstituteEnvironmentVariables
            .yes, SubstituteConfigVariables substituteConfigVariables = SubstituteConfigVariables
            .yes) {
        this(substituteEnvironmentVariables, substituteConfigVariables);
        this.rootNode = rootNode;
    }

    /** 
     * Get values from the configuration using config path notation.
     *
     * Params:
     *   configPath = Path to the wanted config value. The path is separated by dots, e.g. "server.public.hostname". 
     *                Values from arrays can be selected by brackets, for example: "server[3].hostname.ports[0]".
     *                When the config is just a value, for example just a string, it can be fetched by just specifying "." as path.
     *                Although the path should be universally the same over all types of config files, some might not lend to this structure,
     *                and have a more specific way of retrieving data from the config. See the examples and specific config factories for
     *                more details.
     *   defaultValue = (Optional) Value to return when the given configPath is invalid. When not supplied a ConfigPathNotFoundException exception is thrown.
     *
     * Throws: ConfigReadException when something goes wrong reading the config. 
     *         ConfigPathNotFoundException when the given path does not exist in the config.
     *
     * Returns: The value at the path in the configuration. To convert it use get!T().
     */
    string get(string configPath, string defaultValue = null) {
        try {
            auto path = new ConfigPath(configPath);
            auto node = getNodeAt(path);
            auto value = cast(ValueNode) node;
            if (value) {
                if (substituteEnvironmentVariables || substituteConfigVariables) {
                    return substituteVariables(value);
                } else {
                    return value.value;
                }
            } else {
                throw new ConfigReadException(
                    "Value expected but " ~ node.nodeType ~ " found at path: " ~ createExceptionPath(
                        path));
            }
        } catch (ConfigPathNotFoundException e) {
            if (defaultValue !is null) {
                return defaultValue;
            }

            throw e;
        }
    }

    /** 
     * Get values from the configuration and attempts to convert them to the specified type.
     *
     * Params:
     *   configPath = Path to the wanted config value. See get().
     *
     * Throws: ConfigReadException when something goes wrong reading the config. 
     *         ConfigPathNotFoundException when the given path does not exist in the config.
     *
     * Returns: The value at the path in the configuration.
     * See_Also: get
     */
    ConvertToType get(ConvertToType)(string configPath) {
        return get(configPath).to!ConvertToType;
    }

    /** 
     * Get values from the configuration and attempts to convert them to the specified type.
     *
     * Params:
     *   configPath = Path to the wanted config value. See get().
     *   defaultValue = (Optional) Value to return when the given configPath is invalid. When not supplied a ConfigPathNotFoundException exception is thrown.
     *
     * Throws: ConfigReadException when something goes wrong reading the config. 
     *         ConfigPathNotFoundException when the given path does not exist in the config.
     *
     * Returns: The value at the path in the configuration.
     * See_Also: get
     */
    ConvertToType get(ConvertToType)(string configPath, ConvertToType defaultValue) {
        try {
            return get(configPath).to!ConvertToType;
        } catch (ConfigPathNotFoundException e) {
            return defaultValue;
        }
    }

    /** 
     * Fetch a sub-section of the config as another config.
     * 
     * Commonly used for example to fetch  further configuration from arrays, e.g.: `getConfig("http.servers[3]")` 
     * which then returns the rest of the config at that path.
     *
     * Params:
     *   configPath = Path to the wanted config. See get(). 
     * Returns: A sub-section of the configuration.
     */
    ConfigDictionary getConfig(string configPath) {
        auto path = new ConfigPath(configPath);
        auto node = getNodeAt(path);
        return new ConfigDictionary(node);
    }

    /** 
     * Assign a value at the given path.
     * 
     * Params:
     *   configPath = Path where to assign the value to. If the path does not exist, it will be created.
     *   value = Value to set at path.
     */
    void set(string configPath, string value) {
        auto path = new ConfigPath(configPath);
        rootNode = insertAtPath(rootNode, path, value);
    }

    private string createExceptionPath(ConfigPath path) {
        return "'" ~ path.path ~ "' (at '" ~ path.getCurrentPath() ~ "')";
    }

    private ConfigNode getNodeAt(ConfigPath path) {
        void throwPathNotFound() {
            throw new ConfigPathNotFoundException(
                "Path does not exist: " ~ createExceptionPath(path));
        }

        if (rootNode is null) {
            throwPathNotFound();
        }

        auto currentNode = rootNode;
        PathSegment currentPathSegment = path.getNextSegment();

        void ifNotNullPointer(void* obj, void delegate() fn) {
            if (obj) {
                fn();
            } else {
                throwPathNotFound();
            }
        }

        void ifNotNull(Object obj, void delegate() fn) {
            if (obj) {
                fn();
            } else {
                throwPathNotFound();
            }
        }

        while (currentPathSegment !is null) {
            if (currentNode is null) {
                throwPathNotFound();
            }

            auto valueNode = cast(ValueNode) currentNode;
            if (valueNode) {
                throwPathNotFound();
            }

            auto arrayPath = cast(ArrayPathSegment) currentPathSegment;
            if (arrayPath) {
                auto arrayNode = cast(ArrayNode) currentNode;
                ifNotNull(arrayNode, {
                    if (arrayNode.children.length < arrayPath.index) {
                        throw new ConfigReadException(
                            "Array index out of bounds: " ~ createExceptionPath(path));
                    }

                    currentNode = arrayNode.children[arrayPath.index];
                });
            }

            auto propertyPath = cast(PropertyPathSegment) currentPathSegment;
            if (propertyPath) {
                auto objectNode = cast(ObjectNode) currentNode;
                ifNotNull(objectNode, {
                    auto propertyNode = propertyPath.propertyName in objectNode.children;
                    ifNotNullPointer(propertyNode, {
                        currentNode = *propertyNode;
                    });
                });
            }

            currentPathSegment = path.getNextSegment();
        }

        return currentNode;
    }

    private string substituteVariables(ValueNode valueNode) {
        auto value = valueNode.value;
        if (value == null) {
            return value;
        }

        auto result = "";
        auto isParsingEnvVar = false;
        auto isParsingDefault = false;
        auto escapeNextCharacter = false;
        auto varName = "";
        auto defaultVarValue = "";

        void addVarValueToResult() {
            varName = varName.strip;

            if (varName.length == 0) {
                return;
            }

            string[] exceptionMessageParts;

            if (substituteEnvironmentVariables) {
                exceptionMessageParts ~= "environment variable";
                auto envVarValue = environment.get(varName);
                if (envVarValue !is null) {
                    result ~= envVarValue;
                    return;
                }
            }

            if (substituteConfigVariables) {
                exceptionMessageParts ~= "config path";
                auto configValue = get(varName, defaultVarValue);
                if (configValue.length > 0) {
                    result ~= configValue;
                    return;
                }
            }

            if (isParsingDefault) {
                result ~= defaultVarValue.strip;
                return;
            }

            auto exceptionMessageComponents = exceptionMessageParts.join(" or ");
            throw new ConfigReadException(
                "No substitution found for " ~ exceptionMessageComponents ~ ": " ~ varName);
        }

        foreach (size_t i, char c; value) {
            if (escapeNextCharacter) {
                result ~= c;
                escapeNextCharacter = false;
                continue;
            }

            if (c == '\\' && value.length.to!int - 1 > i && value[i + 1] == '$') {
                escapeNextCharacter = true;
                continue;
            }

            if (c == '$') {
                isParsingEnvVar = true;
                continue;
            }

            if (isParsingEnvVar) {
                if (c == '{') {
                    continue;
                }

                if (c == '}') {
                    addVarValueToResult();
                    isParsingEnvVar = false;
                    isParsingDefault = false;
                    varName = "";
                    defaultVarValue = "";
                    continue;
                }

                if (isParsingDefault) {
                    defaultVarValue ~= c;
                    continue;
                }

                if (c == ':') {
                    isParsingDefault = true;
                    continue;
                }

                varName ~= c;
                continue;
            }

            result ~= c;
        }

        if (isParsingEnvVar) {
            if (varName.length > 0) {
                addVarValueToResult();
            } else {
                result ~= '$';
            }
        }

        return result;
    }

    private ConfigNode insertAtPath(ConfigNode node, ConfigPath path, const string value) {
        auto nextSegment = path.getNextSegment();
        if (nextSegment is null) {
            return new ValueNode(value);
        }

        auto propertySegment = cast(PropertyPathSegment) nextSegment;
        if (propertySegment is null) {
            throw new Exception("Not yet implemented: cannot set array"); // todo
        }

        auto objectNode = node is null ? new ObjectNode() : cast(ObjectNode) node;
        if (objectNode is null) {
            throw new Exception("Not yet implemented: cannot set array"); // todo
        }

        auto childNodePtr = propertySegment.propertyName in objectNode.children;
        ConfigNode childNode = childNodePtr !is null ? *childNodePtr : new ObjectNode();
        objectNode.children[propertySegment.propertyName] = insertAtPath(childNode, path, value);
        return objectNode;
    }
}

/** 
 * The base class used by configuration factories for specific file types.
 */
abstract class ConfigFactory {
    /** 
     * Loads a configuration from the specified path from disk.
     *
     * Params:
     *   path = Path to file. OS dependent, but UNIX paths are generally working.
     * Returns: The parsed configuration.
     */
    ConfigDictionary loadFile(string path) {
        auto json = readText(path);
        return parseConfig(json);
    }

    /**
     * Parse configuration from the given string.
     *
     * Params:
     *   contents = Text contents of the config to be parsed.
     * Returns: The parsed configuration.
     */
    ConfigDictionary parseConfig(string contents);
}

/** 
 * Load config from disk.
 * A specific loader will be used based on the file's extension.
 * Params:
 *   configPath = Path to the configuration file.
 * Returns: The loaded configuration.
 * Throws: ConfigCreationException when the file's extension is unrecognized.
 */
ConfigDictionary loadConfig(const string configPath) {
    auto extension = configPath.extension.toLower;
    if (extension == ".json") {
        return loadJsonConfig(configPath);
    }

    if (extension == ".properties") {
        return loadJavaProperties(configPath);
    }

    if (extension == ".ini") {
        return loadIniConfig(configPath);
    }

    throw new ConfigCreationException(
        "File extension '" ~ extension ~ "' is not recognized as a supported config file format. Please use a specific function to load it, such as 'loadJsonConfig()'");
}

version (unittest) {
    import std.exception : assertThrown;
    import std.math.operations : isClose;

    @("Dictionary creation")
    unittest {
        auto root = new ObjectNode([
            "english": new ArrayNode([new ValueNode("one"), new ValueNode("two")]),
            "spanish": new ArrayNode(new ValueNode("uno"), new ValueNode("dos"))
        ]);

        auto config = new ConfigDictionary();
        config.rootNode = root;
    }

    @("Get value in config with empty root fails")
    unittest {
        auto config = new ConfigDictionary();

        assertThrown!ConfigPathNotFoundException(config.get("."));
    }

    @("Get value in root with empty path")
    unittest {
        auto config = new ConfigDictionary(new ValueNode("hehehe"));

        assert(config.get("") == "hehehe");
    }

    @("Get value in root with just a dot")
    unittest {
        auto config = new ConfigDictionary(new ValueNode("yup"));

        assert(config.get(".") == "yup");
    }

    @("Get value in root fails when root is not a value")
    unittest {
        auto config = new ConfigDictionary(new ArrayNode());

        assertThrown!ConfigReadException(config.get("."));
    }

    @("Get array value from root")
    unittest {
        auto config = new ConfigDictionary(new ArrayNode("aap", "noot", "mies"));

        assert(config.get("[0]") == "aap");
        assert(config.get("[1]") == "noot");
        assert(config.get("[2]") == "mies");
    }

    @("Get value from object at root")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode([
                "aap": "monkey",
                "noot": "nut",
                "mies": "mies" // It's a name!
            ])
        );

        assert(config.get("aap") == "monkey");
        assert(config.get("noot") == "nut");
        assert(config.get("mies") == "mies");
    }

    @("Get value from object in object")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                    "server": new ObjectNode([
                        "port": "8080"
                    ])
                ])
        );

        assert(config.get("server.port") == "8080");
    }

    @("Get value from array in object")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "hostname": new ArrayNode(["google.com", "dlang.org"])
            ])
        );

        assert(config.get("hostname.[1]") == "dlang.org");
    }

    @("Exception is thrown when array out of bounds when fetching from root")
    unittest {
        auto config = new ConfigDictionary(
            new ArrayNode([
                    "google.com", "dlang.org"
                ])
        );

        assertThrown!ConfigReadException(config.get("[5]"));
    }

    @("Exception is thrown when array out of bounds when fetching from object")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "hostname": new ArrayNode(["google.com", "dlang.org"])
            ])
        );

        assertThrown!ConfigReadException(config.get("hostname.[5]"));
    }

    @("Exception is thrown when path does not exist")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode(
                [
                    "hostname": new ObjectNode(["cluster": new ValueNode("")])
                ])
        );

        assertThrown!ConfigPathNotFoundException(config.get("hostname.cluster.spacey"));
    }

    @("Exception is thrown when given path terminates too early")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode(
                [
                    "hostname": new ObjectNode(["cluster": new ValueNode(null)])
                ])
        );

        assertThrown!ConfigReadException(config.get("hostname"));
    }

    @("Exception is thrown when given path does not exist because config is an array")
    unittest {
        auto config = new ConfigDictionary(new ArrayNode());

        assertThrown!ConfigPathNotFoundException(config.get("hostname"));
    }

    @("Get value from objects in array")
    unittest {
        auto config = new ConfigDictionary(new ArrayNode(
                new ObjectNode(["wrong": "yes"]),
                new ObjectNode(["wrong": "no"]),
                new ObjectNode(["wrong": "very"]),
        ));

        assert(config.get("[1].wrong") == "no");
    }

    @("Get value from config with mixed types")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "uno": cast(ConfigNode) new ValueNode("one"),
                "dos": cast(ConfigNode) new ArrayNode(["nope", "two"]),
                "tres": cast(ConfigNode) new ObjectNode(["thisone": "three"])
            ])
        );

        assert(config.get("uno") == "one");
        assert(config.get("dos.[1]") == "two");
        assert(config.get("tres.thisone") == "three");
    }

    @("Ignore empty segments")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "one": new ObjectNode(["two": new ObjectNode(["three": "four"])])
            ])
        );

        assert(config.get(".one..two...three....") == "four");
    }

    @("Support conventional array indexing notation")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                    "one": new ObjectNode([
                        "two": new ArrayNode(["dino", "mino"])
                    ])
                ])
        );

        assert(config.get("one.two[1]") == "mino");
    }

    @("Get and convert values")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "uno": new ValueNode("1223"),
                "dos": new ValueNode("true"),
                "tres": new ValueNode("Hi you"),
                "quatro": new ValueNode("1.3")
            ])
        );

        assert(config.get!int("uno") == 1223);
        assert(config.get!bool("dos") == true);
        assert(config.get!string("tres") == "Hi you");
        assert(isClose(config.get!float("quatro"), 1.3));
    }

    @("Get config from array")
    unittest {
        auto configOne = new ConfigDictionary(new ObjectNode(
                [
                "servers": new ArrayNode([
                    new ObjectNode(["hostname": "lala.com"]),
                    new ObjectNode(["hostname": "lele.com"])
                ])
            ])
        );

        auto config = configOne.getConfig("servers[0]");
        assert(config.get("hostname") == "lala.com");
    }

    @("Trim spaces in path segments")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(["que": new ObjectNode(["pasa hombre": "not much"])])
        );

        assert(config.get("  que.    pasa hombre   ") == "not much");
    }

    @("Load configurations using the loadConfig convenience function")
    unittest {
        auto jsonConfig = loadConfig("testfiles/groot.json");
        assert(jsonConfig.get("name") == "Groot");
        assert(jsonConfig.get("traits[1]") == "tree");
        assert(jsonConfig.get("age") == "8728");
        assert(jsonConfig.get("taxNumber") == null);

        auto javaProperties = loadConfig("testfiles/groot.properties");
        assert(javaProperties.get("name") == "Groot");
        assert(javaProperties.get("age") == "8728");
        assert(javaProperties.get("taxNumber") == "null");

        auto iniConfig = loadConfig("testfiles/groot.ini");
        assert(iniConfig.get("groot.name") == "Groot");
        assert(iniConfig.get("groot.age") == "8728");
        assert(iniConfig.get("groot.taxNumber") == "null");
    }

    @("Whitespace is preserved in values")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode([
                "bla": "       blergh       "
            ]));

        assert(config.get("bla") == "       blergh       ");
    }

    @("Null value stays null, not string")
    unittest {
        auto config = new ConfigDictionary(new ValueNode(null));
        assert(config.get(".") == null);
    }

    @("Read value from environment variable")
    unittest {
        environment["MIRAGE_CONFIG_TEST_ENV_VAR"] = "is set!";
        environment["MIRAGE_CONFIG_TEST_ENV_VAR_TWO"] = "is ready!";

        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "withBrackets": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR}"),
                "withoutBrackets": new ValueNode("$MIRAGE_CONFIG_TEST_ENV_VAR"),
                "withWhiteSpace": new ValueNode("        ${MIRAGE_CONFIG_TEST_ENV_VAR}         "),
                "alsoWithWhiteSpace": new ValueNode("    $MIRAGE_CONFIG_TEST_ENV_VAR"),
                "whitespaceAtEnd": new ValueNode("$MIRAGE_CONFIG_TEST_ENV_VAR      "),
                "notSet": new ValueNode("${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR}"),
                "alsoNotSet": new ValueNode("$MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR"),
                "withDefault": new ValueNode("$MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!"),
                "withDefaultAndBrackets": new ValueNode(
                    "${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!}"),
                "megaMix": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR_TWO} ${MIRAGE_CONFIG_TEST_ENV_VAR} ${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:go}!"),
                "typical": new ValueNode("${MIRAGE_CONFIG_TEST_HOSTNAME:localhost}:${MIRAGE_CONFIG_TEST_PORT:8080}"),
                "whitespaceInVar": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR   }"),
                "whitespaceInDefault": new ValueNode("${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:   bruh}"),
                "emptyDefault": new ValueNode("${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:}"),
                "emptyDefaultWhiteSpace": new ValueNode("${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:    }"),
            ]),
        SubstituteEnvironmentVariables.yes,
        SubstituteConfigVariables.no
        );

        assert(config.get("withBrackets") == "is set!");
        assert(config.get("withoutBrackets") == "is set!");
        assert(config.get("withWhiteSpace") == "        is set!         ");
        assert(config.get("alsoWithWhiteSpace") == "    is set!");
        assert(config.get("whitespaceAtEnd") == "is set!");
        assertThrown!ConfigReadException(config.get("notSet")); // Environment variable not found
        assertThrown!ConfigReadException(config.get("alsoNotSet")); // Environment variable not found
        assert(config.get("withDefault") == "use default!");
        assert(config.get("withDefaultAndBrackets") == "use default!");
        assert(config.get("megaMix") == "is ready! is set! go!");
        assert(config.get("typical") == "localhost:8080");
        assert(config.get("whitespaceInVar") == "is set!");
        assert(config.get("whitespaceInDefault") == "bruh");
        assert(config.get("emptyDefault") == "");
        assert(config.get("emptyDefaultWhiteSpace") == "");
    }

    @("Don't read value from environment variables when disabled")
    unittest {
        environment.remove("MIRAGE_CONFIG_TEST_ENV_VAR");
        environment.remove("MIRAGE_CONFIG_TEST_ENV_VAR_TWO");

        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "withBrackets": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR}"),
                "withoutBrackets": new ValueNode("$MIRAGE_CONFIG_TEST_ENV_VAR"),
                "withWhiteSpace": new ValueNode("        ${MIRAGE_CONFIG_TEST_ENV_VAR}         "),
                "alsoWithWhiteSpace": new ValueNode("    $MIRAGE_CONFIG_TEST_ENV_VAR"),
                "tooMuchWhiteSpace": new ValueNode("$MIRAGE_CONFIG_TEST_ENV_VAR      "),
                "notSet": new ValueNode("${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR}"),
                "withDefault": new ValueNode("$MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!"),
                "withDefaultAndBrackets": new ValueNode(
                    "${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!}"),
                "megaMix": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR_TWO} ${MIRAGE_CONFIG_TEST_ENV_VAR} ${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:go}!"),
                "typical": new ValueNode("${MIRAGE_CONFIG_TEST_HOSTNAME:localhost}:${MIRAGE_CONFIG_TEST_PORT:8080}"),
            ]),
        SubstituteEnvironmentVariables.no,
        SubstituteConfigVariables.no
        );

        assert(config.get("withBrackets") == "${MIRAGE_CONFIG_TEST_ENV_VAR}");
        assert(config.get("withoutBrackets") == "$MIRAGE_CONFIG_TEST_ENV_VAR");
        assert(config.get("withWhiteSpace") == "        ${MIRAGE_CONFIG_TEST_ENV_VAR}         ");
        assert(config.get("alsoWithWhiteSpace") == "    $MIRAGE_CONFIG_TEST_ENV_VAR");
        assert(config.get("tooMuchWhiteSpace") == "$MIRAGE_CONFIG_TEST_ENV_VAR      ");
        assert(config.get("notSet") == "${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR}");
        assert(config.get("withDefault") == "$MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!");
        assert(config.get(
                "withDefaultAndBrackets") == "${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:use default!}");
        assert(config.get("megaMix") == "${MIRAGE_CONFIG_TEST_ENV_VAR_TWO} ${MIRAGE_CONFIG_TEST_ENV_VAR} ${MIRAGE_CONFIG_NOT_SET_TEST_ENV_VAR:go}!");
        assert(config.get(
                "typical") == "${MIRAGE_CONFIG_TEST_HOSTNAME:localhost}:${MIRAGE_CONFIG_TEST_PORT:8080}");
    }

    @("Get with default should return default")
    unittest {
        auto config = new ConfigDictionary();
        assert(config.get("la.la.la", "not there") == "not there");
        assert(config.get!int("do.re.mi.fa.so", 42) == 42);
    }

    @("Substitute values from other config paths")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "greet": cast(ConfigNode) new ObjectNode([
                        "env": "Hi"
                    ]),
                "hi": cast(ConfigNode) new ValueNode("${greet.env} there!"),
                "oi": cast(ConfigNode) new ValueNode("${path.does.not.exist}"),
            ]),
        SubstituteEnvironmentVariables.no,
        SubstituteConfigVariables.yes
        );

        assert(config.get("hi") == "Hi there!");
        assertThrown!ConfigReadException(config.get("oi"));
    }

    @("Do not substitute values from other config paths when disabled")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode([
                "greet": cast(ConfigNode) new ObjectNode([
                        "env": "Hi"
                    ]),
                "hi": cast(ConfigNode) new ValueNode("${greet.env} there!"),
                "oi": cast(ConfigNode) new ValueNode("${path.does.not.exist}"),
            ]),
        SubstituteEnvironmentVariables.no,
        SubstituteConfigVariables.no
        );

        assert(config.get("greet.env") == "Hi");
        assert(config.get("hi") == "${greet.env} there!");
        assert(config.get("oi") == "${path.does.not.exist}");
    }

    @("substitute values from both environment variables and config paths")
    unittest {
        environment["MIRAGE_CONFIG_TEST_ENV_VAR_THREE"] = "punch";

        auto config = new ConfigDictionary(
            new ObjectNode([
                "one": new ValueNode("${MIRAGE_CONFIG_TEST_ENV_VAR_THREE}"),
                "two": new ValueNode("${one}"),
            ]),
        SubstituteEnvironmentVariables.yes,
        SubstituteConfigVariables.yes
        );

        assert(config.get("two") == "punch");
    }

    @("Escaping avoids variable substitution")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode([
                "only dollar": "\\$ESCAPE_WITH_MY_LIFE",
                "with brackets": "\\${YOU WON'T GET ME}",
            ])
        );
        assert(config.get("only dollar") == "$ESCAPE_WITH_MY_LIFE");
        assert(config.get("with brackets") == "${YOU WON'T GET ME}");
    }

    @("Wonky values")
    unittest {
        auto config = new ConfigDictionary(new ObjectNode([
                "just a dollar": "$",
                "final escape": "\\",
                "escape with money": "\\$",
                "brackets": "{}",
                "empty bracket money": "${}",
                "smackers": "$$$$$",
                "weird bash escape thingy": "$$",
                "escape room": "\\\\"
            ]));

        assert(config.get("just a dollar") == "$");
        assert(config.get("final escape") == "\\");
        assert(config.get("escape with money") == "$");
        assert(config.get("brackets") == "{}");
        assert(config.get("empty bracket money") == "");
        assert(config.get("smackers") == "$");
        assert(config.get("escape room") == "\\\\");
    }

    @("Set value at path when path does not exist")
    unittest {
        auto config = new ConfigDictionary();
        config.set("do.re.mi.fa.so", "buh");

        assert(config.get("do.re.mi.fa.so") == "buh");
    }

    @("Set value at path when object at path exists")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "one": new ObjectNode([
                    "two": new ObjectNode([
                            "mouseSound": "meep"
                        ])
                ])
            ])
        );

        config.set("one.two.catSound", "meow");

        assert(config.get("one.two.mouseSound") == "meep");
        assert(config.get("one.two.catSound") == "meow");
    }

    @("Overwrite value at path")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "one": new ObjectNode([
                    "two": new ObjectNode([
                            "mouseSound": "meep"
                        ])
                ])
            ])
        );

        config.set("one.two.mouseSound", "yo");

        assert(config.get("one.two.mouseSound") == "yo");
    }

    @("Diverge path completely")
    unittest {
        auto config = new ConfigDictionary(
            new ObjectNode(
                [
                "one": new ObjectNode([
                    "two": new ObjectNode([
                            "mouseSound": "meep"
                        ])
                ])
            ])
        );

        config.set("I.am", "baboon");

        assert(config.get("one.two.mouseSound") == "meep");
        assert(config.get("I.am") == "baboon");
    }

    @("Setting the same value twice will use latest setting")
    unittest {
        auto config = new ConfigDictionary();
        config.set("key", "value");
        config.set("key", "alsoValue");

        assert(config.get("key") == "alsoValue");
    }
}
