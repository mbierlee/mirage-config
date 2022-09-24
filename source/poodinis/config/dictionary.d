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
import std.string : split, startsWith, endsWith, join;
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
    string nodeType();
}

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

interface PathSegment {
}

class ArrayPathSegment : PathSegment {
    const size_t index;

    this(const size_t index) {
        this.index = index;
    }
}

class PropertyPathSegment : PathSegment {
    const string propertyName;

    this(const string propertyName) {
        this.propertyName = propertyName;
    }
}

class ConfigPath {
    private const string path;
    private string[] previousSegments;
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
                throw new PathParseException("Array index '" ~ indexString ~ "' is not acceptable as an array number", path);
            }
        }

        return ret(new PropertyPathSegment(segment));
    }

    string getCurrentPath() {
        return previousSegments.join(".");
    }
}

class ConfigDictionary {
    ConfigNode rootNode;

    string get(string configPath) {
        enforce!ConfigReadException(rootNode !is null, "The config is empty");
        enforce!ConfigReadException(configPath.length > 0, "Supplied config path is empty");

        if (configPath == ".") {
            auto rootValue = cast(ValueNode) rootNode;
            if (rootValue) {
                return rootValue.value;
            } else {
                throw new ConfigReadException("The root of the config is not a value type");
            }
        }

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
}

version (unittest) {
    import std.exception : assertThrown;

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

    @("Get value in dictionary with empty path fails")
    unittest {
        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = new ValueNode("hehehe");

        assertThrown!ConfigReadException(dictionary.get(""));
    }

    @("Get value in root")
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

}
