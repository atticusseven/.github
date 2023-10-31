const core = require("@actions/core");
const github = require("@actions/github");
const fs = require("fs");

try {
  const workspace = core.getInput("workspace");
  const auth_json_filename = workspace + "/" + core.getInput("json_filename");

  const auth_json = {
    "http-basic": {
      "connect.advancedcustomfields.com": {
        username: core.getInput("acf_licence_key"),
        password: core.getInput("site_url"),
      },
    },
    bearer: {
      "composer.admincolumns.com": core.getInput("ac_token"),
    },
  };

  const auth_json_string = JSON.stringify(auth_json);
  //console.log(json);

  fs.writeFile(auth_json_filename, auth_json_string, (err) => {
    // Checking for errors
    if (err) throw err;

    console.log("Done writing"); // Success
  });
} catch (error) {
  core.setFailed(error.message);
}
