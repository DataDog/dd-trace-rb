require 'json'
require "psych"
# rubocop:disable Metrics/BlockLength
namespace :github do
  namespace :actions do
    task :test_template do |t|
      runtimes = [
        "ruby:3.3",
        "ruby:3.2",
        "ruby:3.1",
        "ruby:3.0",
      ].map do |runtime|
        engine, version = runtime.split(':')
        runtime_alias = "#{engine}-#{version.gsub('.', '')}"

        OpenStruct.new(
          "engine" => engine,
          "version" => version,
          "alias" => runtime_alias,
          "image" => "ghcr.io/datadog/images-rb/engines/#{engine}:#{version}"
        )
      end

      test_jobs = runtimes.map do |runtime|
        {
          "test-#{runtime.alias}" => {
            "name" => "Test on #{runtime.engine} #{runtime.version}",
            "needs" => ["compute_tasks"],
            "runs-on" => "ubuntu-22.04",
            "strategy" => {
              "fail-fast" => false,
              "matrix" => {
                "include" => "${{ fromJson(needs.compute_tasks.outputs.#{runtime.alias}-matrix) }}"
              }
            },
            "container" => { "image" => runtime.image },
            "steps" => [
              { "uses" => "actions/checkout@v4" },
              { "run" => "bundle install" },
              { "run" => "bundle exec rake test:${{ matrix.task }}" }
            ]
          }
        }
      end

      compute_tasks = {
        "runs-on" => "ubuntu-22.04",
        "strategy" => {
          "fail-fast" => false,
          "matrix" => {
            "engine" => runtimes.map do |runtime|
              { "name" => runtime.engine, "version" => runtime.version, "alias" => runtime.alias }
            end
          }
        },
        "container" =>{
          "image" => "ghcr.io/datadog/images-rb/engines/${{ matrix.engine.name }}:${{ matrix.engine.version }}"
        },
        "outputs" => runtimes.each_with_object({}) do |runtime, hash|
          hash["#{runtime.alias}-matrix"] = "${{ steps.set-matrix.outputs.#{runtime.alias} }}"
        end,
        "steps" => [
          { "uses" => "actions/checkout@v4" },
          { "run" => "apt update && apt install jq -y" },
          { "run" => "bundle install" },
          {
            "id" => "set-matrix",
            "run" => <<~BASH
              matrix_json=$(bundle exec rake github:generate_matrix)
              # Debug output
              echo "Generated JSON:"
              echo "$matrix_json"
              # Set the output
              echo "${{ matrix.engine.alias }}=$(echo "$matrix_json" | jq -c .)" >> $GITHUB_OUTPUT
            BASH
          },
        ]
      }

      base = {
        "name" => 'Test',
        "on" => ['push'],
        "jobs" => {
          "compute_tasks" => compute_tasks,
          **test_jobs.reduce(&:merge)
        }
      }

      string = +""
      string << <<~EOS
        # Please do NOT manually edit this file.
        # This file is generated by 'bundle exec rake #{t.name}'
      EOS
      string << Psych.dump(base, line_width: 120)

      File.binwrite(".github/workflows/test.yml", string)
    end
  end

  task :generate_matrix do
    matrix = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval

    matrix = matrix.slice("stripe")

    ruby_version = RUBY_VERSION[0..2]
    major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments
    ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"
    array = []
    matrix.each do |key, spec_metadata|
      matched = spec_metadata.any? do |appraisal_group, rubies|
        if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      if matched
        array << { task: key }
      end
    end

    puts JSON.pretty_generate(array)
  end
end
# rubocop:enable Metrics/BlockLength
