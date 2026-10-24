require "minitest/autorun"
require "yaml"
require "json"
require "tmpdir"
require "open3"
require "fileutils"

class DeployTest < Minitest::Test
  ACTION = YAML.load_file(File.expand_path("../action.yml", __dir__))
  BASELINE = YAML.load_file(File.join(__dir__, "baseline.yml"))
  LEGACY_ACTIVATION = ["Activate production plugins", "Activate dev/staging plugins"].freeze

  def setup
    @dir = Dir.mktmpdir("default-deploy-test-")
    @log = File.join(@dir, "commands.jsonl")
    @output = File.join(@dir, "outputs")
    @inputs = ACTION["inputs"].transform_values { |input| input.fetch("default", "") }
    @inputs["destination-path"] = "/isolated/site"
    @outputs = {}
    File.write(File.join(@dir, "wp"), <<~RUBY)
      #!#{RbConfig.ruby}
      require "json"
      File.open(ENV.fetch("COMMAND_LOG"), "a") { |f| f.puts(JSON.generate(ARGV)) }
      command = ARGV.take(3).join(" ")
      if command == ENV["FAIL_COMMAND"]
        warn "Error: simulated WP-CLI failure"
        exit 17
      end
      if ARGV.take(2) == ["plugin", "is-active"] || ARGV.take(2) == ["sg", "status"]
        exit ENV.fetch("CACHE_ACTIVE", "0") == "1" ? 0 : 1
      end
    RUBY
    FileUtils.chmod(0755, File.join(@dir, "wp"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def interpolate(text)
    text.gsub(/\$\{\{\s*(.*?)\s*\}\}/) do
      key = Regexp.last_match(1)
      if key.start_with?("inputs.")
        @inputs.fetch(key.delete_prefix("inputs."))
      elsif key == "steps.plugin-inputs.outputs.plugins"
        @outputs.fetch("plugins", "")
      else
        raise "Unexpected expression: #{key}"
      end
    end
  end

  # Evaluate only the small condition grammar used by this action, not shell code.
  def condition(expression)
    return true unless expression
    @tokens = expression.delete_prefix("${{").delete_suffix("}}").scan(
      /inputs\.[\w-]+|'[^']*'|==|!=|&&|\|\||[()]/
    )
    result = parse_or
    raise "Unexpected condition tokens" unless @tokens.empty?
    result
  end

  def parse_or
    result = parse_and
    while @tokens.first == "||"
      @tokens.shift
      right = parse_and
      result = result || right
    end
    result
  end

  def parse_and
    result = parse_term
    while @tokens.first == "&&"
      @tokens.shift
      right = parse_term
      result = result && right
    end
    result
  end

  def parse_term
    if @tokens.first == "("
      @tokens.shift
      result = parse_or
      raise "Unclosed condition" unless @tokens.shift == ")"
      return result
    end
    left, operator, right = @tokens.shift(3)
    raise "Unsupported condition" unless left&.start_with?("inputs.") && right&.start_with?("'")
    equal = @inputs.fetch(left.delete_prefix("inputs.")).casecmp(right[1...-1]).zero?
    case operator
    when "==" then equal
    when "!=" then !equal
    else raise "Unsupported operator"
    end
  end

  def run_step(step, extra_env = {})
    env = {
      "PATH" => "#{@dir}:#{ENV.fetch('PATH')}",
      "COMMAND_LOG" => @log, "GITHUB_OUTPUT" => @output,
      "BASH_ENV" => "/dev/null"
    }
    step.fetch("env", {}).each { |key, value| env[key] = interpolate(value) }
    stdout, stderr, status = Open3.capture3(
      env.merge(extra_env), "bash", "--noprofile", "--norc", "-eo", "pipefail",
      "-c", interpolate(step.fetch("run")), chdir: @dir
    )
    if File.exist?(@output)
      File.readlines(@output, chomp: true).each do |line|
        key, value = line.split("=", 2)
        @outputs[key] = value
      end
    end
    [status.exitstatus, stdout + stderr]
  end

  def step(name)
    ACTION.fetch("runs").fetch("steps").find { |item| item["name"] == name } || raise(name)
  end

  def commands
    return [] unless File.exist?(@log)
    File.readlines(@log).map { |line| JSON.parse(line) }
  end

  def run_deployment(steps = ACTION["runs"]["steps"], extra_env = {})
    executed = []
    steps.each do |item|
      next unless condition(item["if"])
      # Build, rsync, SSH setup and WP installation are never executed by this harness.
      next unless item["name"] == "Validate optional plugin inputs" ||
                  item.fetch("run", "").lstrip.start_with?("wp ", "if wp ", "read -r -a plugins")
      executed << item["name"]
      code, output = run_step(item, extra_env)
      return [code, output, executed] unless code.zero?
    end
    [0, "", executed]
  end

  def test_existing_inputs_and_every_legacy_step_are_unchanged
    BASELINE["inputs"].each { |name, input| assert_equal input, ACTION["inputs"][name], name }
    original_names = BASELINE["steps"].map { |item| item["name"] }
    assert_equal original_names, ACTION["runs"]["steps"].map { |item| item["name"] } & original_names
    BASELINE["steps"].each do |original|
      current = step(original["name"]).dup
      if LEGACY_ACTIVATION.include?(original["name"])
        environment_condition = original["if"].delete_prefix("${{ ").delete_suffix(" }}")
        environment_condition = "(#{environment_condition})" if environment_condition.include?("||")
        assert_equal "${{ inputs.activate-plugins == '' && #{environment_condition} }}",
                     current["if"]
        current["if"] = original["if"]
      elsif original["name"] == "Flush rewrite rules"
        assert_equal "${{ inputs.flush-rewrites-with-plugins == 'false' }}", current.delete("if")
      end
      assert_equal original, current, original["name"]
    end
    assert_equal "", @inputs["activate-plugins"]
    assert_equal "false", @inputs["flush-rewrites-with-plugins"]
    assert_equal "Validate optional plugin inputs", ACTION["runs"]["steps"].first["name"]
  end

  def test_default_command_sequences_match_baseline
    %w[production dev staging custom].product(%w[0 1]).each do |environment, cache|
      @inputs["env"] = environment
      FileUtils.rm_f(@log)
      original = run_deployment(BASELINE["steps"], "CACHE_ACTIVE" => cache)
      original_commands = commands
      FileUtils.rm_f(@log)
      current = run_deployment(ACTION["runs"]["steps"], "CACHE_ACTIVE" => cache)
      assert_equal original[0], current[0], environment
      assert_equal original_commands, commands, "#{environment}, cache=#{cache}"
      assert_equal original[2], current[2].reject { |name| name == "Validate optional plugin inputs" }
    end
  end

  def test_legacy_failure_handling_matches_baseline
    ["plugin activate --exclude=password-protected,disable-emails",
     "core update-db --skip-plugins", "plugin is-active sg-cachepress",
     "sg status dynamic-cache", "sg purge --skip-themes",
     "rewrite flush --skip-plugins"].each do |failure|
      env = { "FAIL_COMMAND" => failure, "CACHE_ACTIVE" => "1" }
      FileUtils.rm_f(@log)
      original = run_deployment(BASELINE["steps"], env)
      original_commands = commands
      FileUtils.rm_f(@log)
      current = run_deployment(ACTION["runs"]["steps"], env)
      assert_equal original.take(2), current.take(2), failure
      assert_equal original_commands, commands, failure
    end
  end

  def test_explicit_plugins_preserve_arguments_and_order
    lists = ["classic-editor", "a7-events a7-projects a7-resources",
             " \tclassic-editor\r\n  advanced-custom-fields-pro\nadmin_columns\t"]
    %w[production dev staging custom].product(lists).each do |environment, list|
      @inputs["env"] = environment
      @inputs["activate-plugins"] = list
      FileUtils.rm_f(@log)
      assert_equal 0, run_deployment.first
      activations = commands.select { |args| args.take(2) == %w[plugin activate] }
      assert_equal [%w[plugin activate] + list.split +
                    ["--skip-plugins", "--skip-themes", "--ssh=server:/isolated/site"]], activations
      refute commands.any? { |args| args.include?("deactivate") || args.include?("--all") }
    end
  end

  def test_multiline_yaml_example
    list = YAML.load("activate-plugins: >-\n  a7-events\n  a7-projects\n  a7-resources\n")
    @inputs.merge!(list)
    assert_equal 0, run_deployment.first
    assert_equal %w[plugin activate a7-events a7-projects a7-resources], commands.first.take(5)
  end

  def test_invalid_lists_fail_before_any_deployment_command
    [" ", "\n\t\r", "--all", "-bad", "../plugin", "plugin/plugin.php",
     "plugin,name", "UPPERCASE", "plugin.name", "caf\u00e9", "a;touch injected",
     "$(touch injected)", "`touch injected`", "a\n--all", "a|cat", "a&cat",
     "a>injected", "a*"].each do |list|
      @inputs["activate-plugins"] = list
      FileUtils.rm_f(@log)
      code, output, executed = run_deployment
      refute_equal 0, code, list
      assert_includes output, "::error::activate-plugins", list
      assert_equal ["Validate optional plugin inputs"], executed
      assert_empty commands
      refute File.exist?(File.join(@dir, "injected"))
    end
  end

  def test_explicit_failure_is_not_swallowed
    @inputs["activate-plugins"] = "missing-plugin"
    code, output, executed = run_deployment(
      ACTION["runs"]["steps"], "FAIL_COMMAND" => "plugin activate missing-plugin"
    )
    assert_equal 17, code
    assert_includes output, "Error: simulated WP-CLI failure"
    assert_equal "Activate explicit plugins", executed.last
    assert_equal 1, commands.length
  end

  def test_boolean_validation_and_flush_arguments
    %w[false true].each do |value|
      @inputs["flush-rewrites-with-plugins"] = value
      FileUtils.rm_f(@log)
      assert_equal 0, run_deployment.first
      expected = %w[rewrite flush]
      expected += %w[--skip-plugins --skip-themes] if value == "false"
      expected << "--ssh=server:/isolated/site"
      assert_equal [expected], commands.select { |args| args.take(2) == %w[rewrite flush] }
    end
    ["", "TRUE", "False", "yes", "1", "0", " true", "false\n", "$(touch injected)"].each do |value|
      @inputs["flush-rewrites-with-plugins"] = value
      FileUtils.rm_f(@log)
      code, output, executed = run_deployment
      refute_equal 0, code
      assert_includes output, "::error::flush-rewrites-with-plugins"
      assert_equal ["Validate optional plugin inputs"], executed
      assert_empty commands
    end
  end

  def test_destination_in_opt_in_paths_is_data
    @inputs["activate-plugins"] = "classic-editor"
    @inputs["flush-rewrites-with-plugins"] = "true"
    @inputs["destination-path"] = "/path with spaces/$(touch injected)"
    assert_equal 0, run_step(step("Validate optional plugin inputs")).first
    ["Activate explicit plugins", "Flush rewrite rules with plugins and theme"].each do |name|
      assert_equal 0, run_step(step(name)).first
    end
    commands.each { |args| assert_equal "--ssh=server:#{@inputs['destination-path']}", args.last }
    refute File.exist?(File.join(@dir, "injected"))
  end

  def real_wp(*args)
    stdout, stderr, status = Open3.capture3(
      "docker", "exec", ENV.fetch("WP_TEST_CONTAINER"), "wp", "--allow-root", *args
    )
    assert status.success?, "#{args.inspect}\n#{stdout}#{stderr}"
    stdout
  end

  def test_real_wordpress_activation_and_rewrites
    skip "Run test/integration.sh for isolated WordPress integration" unless ENV["WP_TEST_CONTAINER"]
    File.write(File.join(@dir, "wp"), <<~RUBY)
      #!#{RbConfig.ruby}
      args = ARGV.reject { |arg| arg.start_with?("--ssh=") }
      exec "docker", "exec", ENV.fetch("WP_TEST_CONTAINER"), "wp", "--allow-root", *args
    RUBY
    @inputs["activate-plugins"] = "already-active a7-events a7-projects a7-resources"
    @inputs["flush-rewrites-with-plugins"] = "true"
    assert_equal 0, run_step(step("Validate optional plugin inputs")).first
    code, output = run_step(step("Activate explicit plugins"))
    assert_equal 0, code, output
    assert_includes output, "already active"
    assert_equal %w[events projects resources],
                 JSON.parse(real_wp("option", "get", "deployment_test_activation_order", "--format=json"))
    assert_equal %w[a7-events a7-projects a7-resources already-active],
                 real_wp("plugin", "list", "--status=active", "--field=name").split.sort
    assert_equal %w[disable-emails password-protected unrelated-inactive],
                 real_wp("plugin", "list", "--status=inactive", "--field=name").split.sort

    @inputs["activate-plugins"] = "missing-plugin"
    assert_equal 0, run_step(step("Validate optional plugin inputs")).first
    code, output = run_step(step("Activate explicit plugins"))
    refute_equal 0, code
    assert_includes output, "missing-plugin"
    assert_includes output, "Error:"

    real_wp("option", "update", "permalink_structure", "/%postname%/")
    assert_equal 0, run_step(step("Flush rewrite rules")).first
    legacy_rules = JSON.parse(real_wp("option", "get", "rewrite_rules", "--format=json")).keys
    %w[events projects resources project-type theme-items].each do |route|
      refute legacy_rules.any? { |rule| rule.start_with?("#{route}/") }, route
    end
    code, output = run_step(step("Flush rewrite rules with plugins and theme"))
    assert_equal 0, code, output
    rules = JSON.parse(real_wp("option", "get", "rewrite_rules", "--format=json")).keys
    %w[events projects resources project-type theme-items].each do |route|
      assert rules.any? { |rule| rule.start_with?("#{route}/") }, route
    end
  end
end
