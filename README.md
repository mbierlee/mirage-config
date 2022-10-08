# Mirage Config

Version 0.0.0  
Copyright 2022 Mike Bierlee  
Licensed under the terms of the MIT license - See [LICENSE.txt](LICENSE.txt)

Toolkit for loading and using application configuration from various formats.

Features:
- Load from various file formats such as JSON and Java properties;
- Environment variable substitution;
- Internal configuration substitution (Value in config replaced by other path in config);
- Parse configuration from string or JSONValue instead of from disk.

This is a work in progress. More will follow. For now see `examples/` to learn how to use it.

TODO: add tutorial on:
- Config loading
- Config parsing
- Config manip
- Env and config var substitution
-- Escaping