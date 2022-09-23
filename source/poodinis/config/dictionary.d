/**
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module poodinis.config.dictionary;

import std.exception : enforce;
import std.string : split, startsWith, endsWith;
import std.conv : to, ConvException;

class ConfigReadException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class PathParseException : Exception {
    this(string msg, string path, string file = __FILE__, size_t line = __LINE__) {
        string fullMsg = msg ~ " (Path: " ~ path ~ ")";
        super(fullMsg, file, line);
    }
}

interface ConfigNode {
}

class NodeValue : ConfigNode {
    string value;

    this() {
    }

    this(string value) {
        this.value = value;
    }
}

class NodeObject : ConfigNode {
    ConfigNode[string] children;

    this() {
    }

    this(ConfigNode[string] children) {
        this.children = children;
    }
}

class NodeArray : ConfigNode {
    ConfigNode[] children;

    this() {
    }

    this(ConfigNode[] children...) {
        this.children = children;
    }

    this(string[] values...) {
        foreach (string value; values) {
            children ~= new NodeValue(value);
        }
    }
}

class PathSegment {
}

class ArrayPathSegment : PathSegment {
    const size_t index;

    this(const size_t index) {
        this.index = index;
    }
}

class ConfigPath {
    private const string path;
    private string[] segments;

    this(const string path) {
        this.path = path;
        this.segments = path.split(".");
    }

    PathSegment getNextSegment() {
        if (segments.length == 0) {
            return null;
        }

        PathSegment ret(PathSegment segment) {
            segments = segments.length > 1 ? segments[1 .. $] : [];
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
                throw new PathParseException("Array index '" ~ indexString ~ "' is not acceptable as an array number", path);
            }
        }

        throw new Exception("Not yet implemented");
    }
}

class ConfigDictionary {
    ConfigNode rootNode;

    string get(string configPath) {
        enforce!ConfigReadException(rootNode !is null, "The config is empty");
        enforce!ConfigReadException(configPath.length > 0, "Supplied config path is empty");

        if (configPath == ".") {
            auto rootValue = cast(NodeValue) rootNode;
            if (rootValue) {
                return rootValue.value;
            } else {
                throw new ConfigReadException("The root of the config is not a value type");
            }
        }

        auto path = new ConfigPath(configPath);
        auto currentNode = rootNode;
        PathSegment currentPathSegment = path.getNextSegment();
        while (currentPathSegment !is null) {
            auto arrayPath = cast(ArrayPathSegment) currentPathSegment;
            if (arrayPath) {
                auto arrayNode = cast(NodeArray) currentNode;
                if (arrayNode) {
                    currentNode = arrayNode.children[arrayPath.index];
                }
            }

            currentPathSegment = path.getNextSegment();
        }

        auto value = cast(NodeValue) currentNode;
        if (value) {
            return value.value;
        } else {
            throw new ConfigReadException(
                "The configuration at the given path is not a value: " ~ configPath);
        }
    }
}

version (unittest) {
    import std.exception : assertThrown;

    @("Dictionary creation")
    unittest {
        auto root = new NodeObject([
            "english": new NodeArray([new NodeValue("one"), new NodeValue("two")]),
            "spanish": new NodeArray(new NodeValue("uno"), new NodeValue("dos"))
        ]);

        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = root;
    }

    @("Get value in dictionary with empty root fails")
    unittest {
        auto dictionary = new ConfigDictionary();

        assertThrown!ConfigReadException(dictionary.get("."));
    }

    @("Get value in dictionary with empty path fails")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new NodeValue("hehehe");

        assertThrown!ConfigReadException(dictionary.get(""));
    }

    @("Get value in root")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new NodeValue("yup");

        assert(dictionary.get(".") == "yup");
    }

    @("Get value in root fails when root is not a value")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new NodeArray();

        assertThrown!ConfigReadException(dictionary.get("."));
    }

    @("Get array value from root")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new NodeArray("aap", "noot", "mies");

        assert(dictionary.get("[0]") == "aap");
        assert(dictionary.get("[1]") == "noot");
        assert(dictionary.get("[2]") == "mies");
    }
}
