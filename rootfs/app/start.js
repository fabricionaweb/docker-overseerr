#!/usr/bin/env node

// ensure production env
process.env.NODE_ENV = "production";
// it needs to run from the right folder
process.chdir(__dirname);
// start the app
require('./dist/index.js');
