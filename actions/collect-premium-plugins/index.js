const core = require("@actions/core");
const github = require("@actions/github");
const fs = require("fs");
const plugins_json =
  core.getInput("workspace") + "/" + core.getInput("json_filename");
const premium_plugins_dir = "premium-plugins";

try {
  //premium plugins
  const premium_plugins = fs
    .readdirSync(premium_plugins_dir)
    .filter((plugin) => plugin.endsWith(".zip"))
    .map((plugin) => plugin.replace(".zip", ""));
  //console.log(premium_plugins);

  json = JSON.stringify(premium_plugins);
  //console.log(json);

  fs.writeFile(plugins_json, json, (err) => {
    // Checking for errors
    if (err) throw err;

    console.log("Premium Plugins JSON generated"); // Success
  });
} catch (error) {
  core.setFailed(error.message);
}
