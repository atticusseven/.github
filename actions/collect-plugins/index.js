const core = require("@actions/core");
const github = require("@actions/github");
const fs = require("fs");

try {
  const workspace = core.getInput("workspace");
  const plugins_dir = workspace + "/" + core.getInput("plugins_dir");
  const plugins_json = workspace + "/" + core.getInput("json_filename");

  //const plugins_dir = "html/content/plugins";
  const premium_plugins_dir = workspace + "/" + "premium-plugins";
  const composer_json_file = workspace + "/" + "html/composer.json";
  // get the directory contents
  const plugins = fs.readdirSync(plugins_dir);
  const premium_plugins = fs
    .readdirSync(premium_plugins_dir)
    .map((x) => x.replace(".zip", ""));
  //console.log(premium_plugins);
  const exclude = [".DS_Store", "index.php"];

  for (let i = 0; i < exclude.length; i++) {
    let index = plugins.indexOf(exclude[i]);
    if (index > -1) {
      // only splice array when item is found
      plugins.splice(index, 1); // 2nd parameter means remove one item only
    }
  }

  const composer_json = fs.readFileSync(composer_json_file);
  const composer_plugins = Object.getOwnPropertyNames(
    JSON.parse(composer_json)["require"]
  ).map((x) => x.split("/")[1]);
  //console.log(composer_plugins);

  //console.log(files.length);

  let type = "";

  for (let i = 0; i < plugins.length; i++) {
    if (plugins[i].startsWith("a7-")) {
      type = "custom";
    } else if (premium_plugins.includes(plugins[i])) {
      type = "premium";
    } else if (composer_plugins.includes(plugins[i])) {
      type = "composer";
    } else {
      type = "free";
    }
    plugins[i] = {
      name: plugins[i],
      type: type,
    };
  }

  json = JSON.stringify(plugins);
  //console.log(json);

  fs.writeFile(plugins_json, json, (err) => {
    // Checking for errors
    if (err) throw err;

    console.log("Done writing"); // Success
  });
} catch (error) {
  core.setFailed(error.message);
}
