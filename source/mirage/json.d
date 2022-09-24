/**
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

class JsonConfigFactory : ConfigFactory {
    ConfigDictionary loadFile(string path) {
        throw new Exception("not yet implemented");
    }

    ConfigDictionary parseConfig(string contents) {
        return parseJson(parseJSON(contents));
    }

    ConfigDictionary parseJson(JSONValue json) {
        return new ConfigDictionary(convertJValue(json));
    }

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

        auto loader = new JsonConfigFactory();
        auto config = loader.parseJson(jsonConfig);

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
        auto loader = new JsonConfigFactory();

        assert(loader.parseJson(JSONValue("hi")).get(".") == "hi");
        assert(loader.parseJson(JSONValue(1)).get(".") == "1");
        assert(loader.parseJson(JSONValue(null)).get(".") == null);
        assert(loader.parseJson(JSONValue(1.8)).get(".") == "1.8");
        assert(loader.parseJson(JSONValue([1, 2, 3])).get("[2]") == "3");
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

        auto loader = new JsonConfigFactory();
        auto config = loader.parseJson(json);

        assert(config.get("name") == "Groot");
        assert(config.get("traits[1]") == "tree");
        assert(config.get("age") == "8728");
        assert(config.get("taxNumber") == null);
    }
}
