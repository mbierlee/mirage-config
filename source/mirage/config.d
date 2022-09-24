/**
 * Base utilities for working with configurations.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.config;

import std.exception : enforce;
import std.string : split, startsWith, endsWith, join, lastIndexOf;
import std.conv : to, ConvException;
import std.file : readText;

/** 
 * Used by the ConfigDictionary when something goes wrong when reading configuration.
 */
class ConfigReadException : Exception {
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
            if (segment.length <= 0) {
                continue;
            }

            if (segment.endsWith("]") && !segment.startsWith("[")) {
                auto openBracketPos = segment.lastIndexOf("[");
                if (openBracketPos != -1) {
                    segments ~= segment[0 .. openBracketPos];
                    segments ~= segment[openBracketPos .. $];
                    continue;
                }
            }

            segments ~= segment;
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
 * A ConfigDictionary contains the configuration tree and facilities to get values from that tree.
 */
class ConfigDictionary {
    ConfigNode rootNode;

    this() {
    }

    this(ConfigNode rootNode) {
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
     *
     * Returns: The value at the path in the configuration. To convert it use get!T().
     */
    string get(string configPath) {
        enforce!ConfigReadException(rootNode !is null, "The config is empty");

        auto path = new ConfigPath(configPath);
        auto currentNode = rootNode;
        PathSegment currentPathSegment = path.getNextSegment();

        string createExceptionPath() {
            return "'" ~ configPath ~ "' (at '" ~ path.getCurrentPath() ~ "')";
        }

        void throwPathNotExists() {
            throw new ConfigReadException("Path does not exist: " ~ createExceptionPath());
        }

        void ifNotNullPointer(void* obj, void delegate() fn) {
            if (obj) {
                fn();
            } else {
                throwPathNotExists();
            }
        }

        void ifNotNull(Object obj, void delegate() fn) {
            if (obj) {
                fn();
            } else {
                throwPathNotExists();
            }
        }

        while (currentPathSegment !is null) {
            if (currentNode is null) {
                throwPathNotExists();
            }

            auto valueNode = cast(ValueNode) currentNode;
            if (valueNode) {
                throwPathNotExists();
            }

            auto arrayPath = cast(ArrayPathSegment) currentPathSegment;
            if (arrayPath) {
                auto arrayNode = cast(ArrayNode) currentNode;
                ifNotNull(arrayNode, {
                    if (arrayNode.children.length < arrayPath.index) {
                        throw new ConfigReadException(
                            "Array index out of bounds: " ~ createExceptionPath());
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

        auto value = cast(ValueNode) currentNode;
        if (value) {
            return value.value;
        } else {
            throw new ConfigReadException(
                "Value expected but " ~ currentNode.nodeType ~ " found at path: " ~ createExceptionPath());
        }
    }

    /** 
     * Get values from the configuration and attempts to convert them to the specified type.
     *
     * Params:
     *   configPath = Path to the wanted config value. See get(). 
     * Returns: The value at the path in the configuration.
     */
    ConvertToType get(ConvertToType)(string configPath) {
        return get(configPath).to!ConvertToType;
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

version (unittest) {
    import std.exception : assertThrown;
    import std.math.operations : isClose;

    @("Dictionary creation")
    unittest {
        auto root = new ObjectNode([
            "english": new ArrayNode([new ValueNode("one"), new ValueNode("two")]),
            "spanish": new ArrayNode(new ValueNode("uno"), new ValueNode("dos"))
        ]);

        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = root;
    }

    @("Get value in dictionary with empty root fails")
    unittest {
        auto dictionary = new ConfigDictionary();

        assertThrown!ConfigReadException(dictionary.get("."));
    }

    @("Get value in root with empty path")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ValueNode("hehehe");

        assert(dictionary.get("") == "hehehe");
    }

    @("Get value in root with just a dot")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ValueNode("yup");

        assert(dictionary.get(".") == "yup");
    }

    @("Get value in root fails when root is not a value")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ArrayNode();

        assertThrown!ConfigReadException(dictionary.get("."));
    }

    @("Get array value from root")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ArrayNode("aap", "noot", "mies");

        assert(dictionary.get("[0]") == "aap");
        assert(dictionary.get("[1]") == "noot");
        assert(dictionary.get("[2]") == "mies");
    }

    @("Get value from object at root")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "aap": "monkey",
            "noot": "nut",
            "mies": "mies" // It's a name!
        ]);

        assert(dictionary.get("aap") == "monkey");
        assert(dictionary.get("noot") == "nut");
        assert(dictionary.get("mies") == "mies");
    }

    @("Get value from object in object")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "server": new ObjectNode([
                    "port": "8080"
                ])
        ]);

        assert(dictionary.get("server.port") == "8080");
    }

    @("Get value from array in object")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "hostname": new ArrayNode(["google.com", "dlang.org"])
        ]);

        assert(dictionary.get("hostname.[1]") == "dlang.org");
    }

    @("Exception is thrown when array out of bounds when fetching from root")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ArrayNode(["google.com", "dlang.org"]);

        assertThrown!ConfigReadException(dictionary.get("[5]"));
    }

    @("Exception is thrown when array out of bounds when fetching from object")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "hostname": new ArrayNode(["google.com", "dlang.org"])
        ]);

        assertThrown!ConfigReadException(dictionary.get("hostname.[5]"));
    }

    @("Exception is thrown when path does not exist")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode(
            [
                "hostname": new ObjectNode(["cluster": new ValueNode("")])
            ]);

        assertThrown!ConfigReadException(dictionary.get("hostname.cluster.spacey"));
    }

    @("Exception is thrown when given path terminates too early")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode(
            [
                "hostname": new ObjectNode(["cluster": new ValueNode(null)])
            ]);

        assertThrown!ConfigReadException(dictionary.get("hostname"));
    }

    @("Exception is thrown when given path does not exist because config is an array")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ArrayNode();

        assertThrown!ConfigReadException(dictionary.get("hostname"));
    }

    @("Get value from objects in array")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ArrayNode(
            new ObjectNode(["wrong": "yes"]),
            new ObjectNode(["wrong": "no"]),
            new ObjectNode(["wrong": "very"]),
        );

        assert(dictionary.get("[1].wrong") == "no");
    }

    @("Get value from config with mixed types")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "uno": cast(ConfigNode) new ValueNode("one"),
            "dos": cast(ConfigNode) new ArrayNode(["nope", "two"]),
            "tres": cast(ConfigNode) new ObjectNode(["thisone": "three"])
        ]);

        assert(dictionary.get("uno") == "one");
        assert(dictionary.get("dos.[1]") == "two");
        assert(dictionary.get("tres.thisone") == "three");
    }

    @("Ignore empty segments")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode(
            [
                "one": new ObjectNode(["two": new ObjectNode(["three": "four"])])
            ]);

        assert(dictionary.get(".one..two...three....") == "four");
    }

    @("Support conventional array indexing notation")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode(
            [
                "one": new ObjectNode(["two": new ArrayNode(["dino", "mino"])])
            ]);

        assert(dictionary.get("one.two[1]") == "mino");
    }

    @("Get and convert values")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ObjectNode([
            "uno": new ValueNode("1223"),
            "dos": new ValueNode("true"),
            "tres": new ValueNode("Hi you"),
            "quatro": new ValueNode("1.3")
        ]);

        assert(dictionary.get!int("uno") == 1223);
        assert(dictionary.get!bool("dos") == true);
        assert(dictionary.get!string("tres") == "Hi you");
        assert(isClose(dictionary.get!float("quatro"), 1.3));
    }
}
