module poodinis.config.dictionary;

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
}

class ConfigDictionary {
    ConfigNode rootNode;
}

version (unittest) {
    @("Dictionary creation")
    unittest {
        auto root = new NodeObject([
            "english": new NodeArray([new NodeValue("one"), new NodeValue("two")]),
            "spanish": new NodeArray(new NodeValue("uno"), new NodeValue("dos"))
        ]);

        auto dictionary = new ConfigDictionary();
        dictionary.rootNode = root;
    }
}
