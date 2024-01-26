const core = require("@actions/core");
const github = require("@actions/github");
const fs = require("fs");

try {
  const workspace = core.getInput("workspace");
  const root_dir = core.getInput("root_dir");
  const composer_json_file = workspace + "/" + root_dir + "/composer.json";
  const composer_json = fs.readFileSync(composer_json_file);
  console.log(composer_json);
  //const composer = JSON.parse(composer_json);
  //console.log(composer);

  const dev_only_plugins_json = core.getInput("dev_only_plugins");
  console.log(dev_only_plugins_json);
  const dev_only_plugins = JSON.parse(dev_only_plugins_json);
  console.log(dev_only_plugins);

  return;

  for (let i = 0; i < dev_only_plugins.length; i++) {
    delete composer.require["wpackagist-plugin/" + dev_only_plugins[i]];
  }

  json = JSON.stringify(composer);

  fs.writeFile(composer_json_file, json, (err) => {
    // Checking for errors
    if (err) throw err;

    console.log("Done writing"); // Success
  });
} catch (error) {
  core.setFailed(error.message);
}
