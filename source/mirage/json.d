/**
 * Utilities for loading JSON configurations.
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2022 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE file.
 */

module mirage.json;

import std.json : JSONValue, JSONType, parseJSON;
import std.conv : to;

import mirage.config : ConfigFactory, ConfigDictionary, ConfigNode, ValueNode, ObjectNode, ArrayNode, ConfigCreationException;

/** 
 * Creates configuration dictionaries from JSONs.
 */
class JsonConfigFactory : ConfigFactory {

    /**
     * Parse configuration from the given JSON string.
     *
     * Params:
     *   contents = Text contents of the config to be parsed.
     * Returns: The parsed configuration.
     */
    override ConfigDictionary parseConfig(string contents) {
        return parseJson(parseJSON(contents));
    }

    /** 
     * Parse configuration from a JSONValue tree. 
     *
     * Params:
     *   contents = JSONValue config to be parsed.
     * Returns: The parsed configuration.
     */
    ConfigDictionary parseJson(JSONValue json) {
        return new ConfigDictionary(convertJValue(json));
    }

    /** 
     * Alias for parseConfig
     *
     * Params:
     *   contents = Text contents of the config to be parsed.
     * Returns: The parsed configuration.
     * See_Also: parseConfig
     */
    ConfigDictionary parseJson(string json) {
        return parseConfig(json);
    }

    private ConfigNode convertJValue(JSONValue json) {
        if (json.type() == JSONType.object) {
            auto objectNode = new ObjectNode();
            auto objectJson = json.object();
            foreach (propertyName, jvalue; objectJson) {
                objectNode.children[propertyName] = convertJValue(jvalue);
            }

            return objectNode;
        }

        if (json.type() == JSONType.array) {
            auto arrayNode = new ArrayNode();
            auto arrayJson = json.array();
            foreach (jvalue; arrayJson) {
                arrayNode.children ~= convertJValue(jvalue);
            }

            return arrayNode;
        }

        if (json.type() == JSONType.null_) {
            return new ValueNode(null);
        }

        if (json.type() == JSONType.string) {
            return new ValueNode(json.get!string);
        }

        if (json.type() == JSONType.integer) {
            return new ValueNode(json.integer.to!string);
        }

        if (json.type() == JSONType.float_) {
            return new ValueNode(json.floating.to!string);
        }

        throw new ConfigCreationException("JSONValue is not supported: " ~ json.toString());
    }
}

/** 
 * Parse JSON config from the given JSON string.

 * Params:
 *   json = Text contents of the config to be parsed.
 * Returns: The parsed configuration.
 */
ConfigDictionary parseJsonConfig(string json) {
    return new JsonConfigFactory().parseConfig(json);
}

/** 
 * Parse JSON config from the given JSONValue.
 *
 * Params:
 *   contents = JSONValue config to be parsed.
 * Returns: The parsed configuration.
 */
ConfigDictionary parseJsonConfig(JSONValue json) {
    return new JsonConfigFactory().parseJson(json);
}

/** 
 * Load a JSON configuration file from disk.
 *
 * Params:
 *   filePath = Path to the JSON configuration file.
 * Returns: The loaded configuration.
 */
ConfigDictionary loadJsonConfig(string filePath) {
    return new JsonConfigFactory().loadFile(filePath);
}

version (unittest) {
    @("Parse JSON")
    unittest {
        JSONValue serverJson = ["hostname": "hosty.com", "port": "1234"];
        JSONValue nullJson = ["isNull": null];
        JSONValue socketsJson = [
            "/var/sock/one", "/var/sock/two", "/var/sock/three"
        ];
        JSONValue numbersJson = [1, 2, 3, 4, -7];
        JSONValue decimalsJson = [1.2, 4.5, 6.7];
        JSONValue jsonConfig = [
            "server": serverJson, "sockets": socketsJson, "nully": nullJson,
            "numberos": numbersJson, "decimalas": decimalsJson
        ];

        auto config = parseJsonConfig(jsonConfig);

        assert(config.get("server.hostname") == "hosty.com");
        assert(config.get("server.port") == "1234");
        assert(config.get("sockets[2]") == "/var/sock/three");
        assert(config.get("nully.isNull") == null);
        assert(config.get("numberos[3]") == "4");
        assert(config.get("numberos[4]") == "-7");
        assert(config.get("decimalas[0]") == "1.2");
        assert(config.get("decimalas[2]") == "6.7");
    }

    @("Parse JSON root values")
    unittest {
        assert(parseJsonConfig(JSONValue("hi")).get(".") == "hi");
        assert(parseJsonConfig(JSONValue(1)).get(".") == "1");
        assert(parseJsonConfig(JSONValue(null)).get(".") == null);
        assert(parseJsonConfig(JSONValue(1.8)).get(".") == "1.8");
        assert(parseJsonConfig(JSONValue([1, 2, 3])).get("[2]") == "3");
    }

    @("Parse JSON string")
    unittest {
        string json = "
            {
                \"name\": \"Groot\",
                \"traits\": [\"groot\", \"tree\"],
                \"age\": 8728,
                \"taxNumber\": null
            } 
        ";

        auto config = parseJsonConfig(json);

        assert(config.get("name") == "Groot");
        assert(config.get("traits[1]") == "tree");
        assert(config.get("age") == "8728");
        assert(config.get("taxNumber") == null);
    }

    @("Load JSON file")
    unittest {
        auto config = loadJsonConfig("testfiles/groot.json");

        assert(config.get("name") == "Groot");
        assert(config.get("traits[1]") == "tree");
        assert(config.get("age") == "8728");
        assert(config.get("taxNumber") == null);
    }
}
