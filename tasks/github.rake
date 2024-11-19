require 'json'
require "psych"
require 'ostruct'
require_relative 'appraisal_conversion'

# rubocop:disable Metrics/BlockLength
namespace :github do
  namespace :actions do
    task :test_template do |t|
      ubuntu = "ubuntu-22.04"

      docker_login_credentials = {
        "username" => '${{ secrets.DOCKERHUB_USERNAME }}',
        "password" => '${{ secrets.DOCKERHUB_TOKEN }}'
      }

      postgres = {
        "image" => "postgres:9.6",
        "credentials" => docker_login_credentials.dup,
        "env" => {
          "POSTGRES_PASSWORD" => "postgres",
          "POSTGRES_USER" => "postgres",
          "POSTGRES_DB" => "postgres",
        }
      }

      redis = {
        "image" => "redis:6.2",
        "credentials" => docker_login_credentials.dup,
      }

      runtimes = [
        "ruby:3.3",
        # "ruby:3.2",
        # "ruby:3.1",
        # "ruby:3.0",
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
            "name" => "#{runtime.engine}-#{runtime.version}: ${{ matrix.task }} (${{ matrix.group }})",
            "needs" => ["compute_tasks"],
            "runs-on" => ubuntu,
            "strategy" => {
              "fail-fast" => false,
              "matrix" => {
                "include" => "${{ fromJson(needs.compute_tasks.outputs.#{runtime.alias}-matrix) }}"
              }
            },
            "container" => {
              "image" => runtime.image,
              "env" => {
                "TEST_POSTGRES_HOST" => "postgres",
                "TEST_REDIS_HOST" => "redis",
              }
            },
            "services" => {
              "postgres" => postgres,
              "redis" => redis
            },
            "steps" => [
              { "uses" => "actions/checkout@v4" },
              {
                "name" => "Configure Git",
                "run" => 'git config --global --add safe.directory "$GITHUB_WORKSPACE"'
              },
              {
                "uses" => "actions/download-artifact@v4",
                "with" => {
                  "name" => "bundled-dependencies-${{ github.run_id }}-#{runtime.alias}",
                }
              },
              { "run" => "bundle install --local" },
              {
                "name" => "Test ${{ matrix.task }} with ${{ matrix.gemfile }}",
                "env" => { "BUNDLE_GEMFILE" => "${{ matrix.gemfile }}" },
                "run" => "bundle install && bundle exec rake spec:${{ matrix.task }}"
              }
            ]
          }
        }
      end

      compute_tasks = {
        "runs-on" => ubuntu,
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
          {
            "run" => <<~BASH
              curl -L --retry 3 -f --retry-all-errors --retry-delay 1 -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux64
              chmod +x /usr/local/bin/jq
            BASH
          },
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
          { "run" => "bundle cache" },
          {
            "uses" => "actions/upload-artifact@v4",
            "with" => {
              "name" => "bundled-dependencies-${{ github.run_id }}-${{ matrix.engine.alias }}",
              "retention-days" => 1,
              "path" => <<~STRING
                Gemfile.lock
                vendor/
              STRING
            }
          },
        ]
      }

      base = {
        "name" => 'Test',
        "on" => ['push'],
        "concurrency" => {
          "group" => '${{ github.workflow }}-${{ github.ref }}',
          "cancel-in-progress" => '${{ github.ref != \'refs/heads/master\' }}'
        },
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

    candidates = [
      'main',
      'pg',
      'rack',
      'redis',
      'stripe'
    ]

    remainders = matrix.keys - candidates

    if remainders.empty?
      raise "No remainder found. Use the matrix directly (without candidate filtering)."
    end

    matrix = matrix.slice(*candidates)

    ruby_version = RUBY_VERSION[0..2]
    major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments
    ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"
    array = []
    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end

        if matched
          gemfile = AppraisalConversion.to_bundle_gemfile(group) rescue "Gemfile"

          array << {
            group: group,
            gemfile: gemfile,
            task: key
          }
        end
      end

    end

    puts JSON.pretty_generate(array)
  end
end
# rubocop:enable Metrics/BlockLength
