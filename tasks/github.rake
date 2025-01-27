require 'json'
require 'psych'
require 'ostruct'
require_relative 'appraisal_conversion'

# rubocop:disable Metrics/BlockLength
namespace :github do
  namespace :actions do
    task :test_template do |t|
      ubuntu = 'ubuntu-24.04'

      # Still being rate limited
      docker_login_credentials = {
        'username' => '${{ secrets.DOCKERHUB_USERNAME }}',
        'password' => '${{ secrets.DOCKERHUB_TOKEN }}'
      }

      postgres = {
        'image' => 'postgres:9.6',
        'credentials' => docker_login_credentials,
        'env' => {
          'POSTGRES_PASSWORD' => 'postgres',
          'POSTGRES_USER' => 'postgres',
          'POSTGRES_DB' => 'postgres',
        }
      }

      redis = {
        'image' => 'redis:6.2',
        'credentials' => docker_login_credentials,
      }

      runtimes = [
        'ruby:3.3',
        # "ruby:3.2",
        # "ruby:3.1",
        # "ruby:3.0",
        # "ruby:2.7",
        # "ruby:2.6",
        # "ruby:2.5",
        "jruby:9.4",
        # "jruby:9.3",
        # "jruby:9.2",
      ].map do |runtime|
        engine, version = runtime.split(':')
        runtime_alias = "#{engine}-#{version.delete('.')}"

        OpenStruct.new(
          'engine' => engine,
          'version' => version,
          'alias' => runtime_alias,
          'image' => "ghcr.io/datadog/images-rb/engines/#{engine}:#{version}",
          'build_id' => "build-#{runtime_alias}",
          'test_id' => "test-#{runtime_alias}",
          'lockfile_artifact' => "bundled-lockfile-#{runtime_alias}-${{ github.run_id }}",
          'dependencies_artifact' => "bundled-dependencies-#{runtime_alias}-${{ github.run_id }}"
        )
      end

      jobs = {}

      runtimes.each do |runtime|
        jobs[runtime.build_id] = {
          'runs-on' => ubuntu,
          'name' => "Build #{runtime.engine}-#{runtime.version}",
          'outputs' => {
            "#{runtime.alias}-batches" => "${{ steps.set-batches.outputs.#{runtime.alias}-batches }}"
          },
          'container' => {
            'image' => runtime.image
          },
          'steps' => [
            { 'uses' => 'actions/checkout@v4' },
            { 'run' => 'bundle install' },
            {
              'uses' => 'actions/upload-artifact@v4',
              'with' => {
                'name' => runtime.lockfile_artifact,
                'retention-days' => 1,
                'path' => 'Gemfile.lock'
              }
            },
            {
              'id' => 'set-batches',
              'run' => <<~BASH
                batches_json=$(bundle exec rake github:generate_batches)
                # Debug output
                echo "Generated JSON:"
                echo "$batches_json"
                # Set the output
                echo "#{runtime.alias}-batches=$batches_json" >> $GITHUB_OUTPUT
              BASH
            },
            { 'run' => 'bundle exec rake dependency:install' },
            {
              'uses' => 'actions/upload-artifact@v4',
              'with' => {
                'name' => runtime.dependencies_artifact,
                'retention-days' => 1,
                'path' => '/usr/local/bundle'
              }
            }
          ]
        }

        jobs[runtime.test_id] = {
          'needs' => [runtime.build_id],
          'runs-on' => ubuntu,
          'name' => "Test #{runtime.engine}-#{runtime.version}[${{ matrix.batch }}]",
          'strategy' => {
            'fail-fast' => false,
            'matrix' => {
              'include' => "${{ fromJson(needs.#{runtime.build_id}.outputs.#{runtime.alias}-batches).include }}"
            }
          },
          'container' => {
            'image' => runtime.image,
            'env' => {
              'TEST_POSTGRES_HOST' => 'postgres',
              'TEST_REDIS_HOST' => 'redis',
            }
          },
          'services' => {
            'postgres' => postgres,
            'redis' => redis,
          },
          'steps' => [
            { 'uses' => 'actions/checkout@v4' },
            {
              'name' => 'Configure Git',
              'run' => 'git config --global --add safe.directory "$GITHUB_WORKSPACE"'
            },
            {
              'uses' => 'actions/download-artifact@v4',
              'with' => {
                'name' => runtime.lockfile_artifact,
              }
            },
            {
              'uses' => 'actions/download-artifact@v4',
              'with' => {
                'name' => runtime.dependencies_artifact,
                'path' => '/usr/local/bundle'
              }
            },
            { 'run' => 'bundle install' },
            {
              'name' => 'Run batched tests',
              'timeout-minutes' => 30,
              'env' => { 'BATCHED_TASKS' => '${{ toJSON(matrix.tasks) }}' },
              'run' => 'bundle exec rake github:run_batch_tests'
            },
            {
              'if' => "env.RUNNER_DEBUG == '1' && failure()",
              'uses' => 'mxschmitt/action-tmate@v3',
              'with' => {
                'limit-access-to-actor' => true,
              }
            },
          ]
        }
      end

      base = {
        'name' => 'Unit Tests',
        'on' => {
          'push' => {
            'branches' => [
              'master',
              'poc/**',
            ]
          },
          'schedule' => [
            { 'cron' => '0 7 * * *' }
          ]
        },
        'concurrency' => {
          'group' => '${{ github.workflow }}-${{ github.ref }}',
          'cancel-in-progress' => '${{ github.ref != \'refs/heads/master\' }}'
        },
        'jobs' => jobs.merge('aggregate' => {
          'runs-on' => ubuntu,
          'needs' => runtimes.map(&:test_id),
          'steps' => [
            'run' => 'echo "DONE!"'
          ]
        })
      }

      # `Psych.dump` directly creates anchors, but Github Actions does not support anchors for YAML,
      # convert to JSON first to avoid anchors
      json = JSON.dump(base)
      yaml = Psych.safe_load(json)

      string = +''
      string << <<~COMMENT
        # Please do NOT manually edit this file.
        # This file is generated by 'bundle exec rake #{t.name}'
      COMMENT
      string << Psych.dump(yaml, line_width: 120)
      File.binwrite('.github/workflows/test.yml', string)
    end
  end

  task :generate_batches do
    matrix = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval

    candidates = [
      'main',
      # 'crashtracking',
      'appsec:main',
      'profiling:main',
      'profiling:ractors',
      'contrib',
      'opentelemetry',
      # "action_pack",
      'action_view',
      'active_model_serializers',
      # "active_record",
      'active_support',
      'autoinstrument',
      'aws',
      'concurrent_ruby',
      # 'dalli',
      # "delayed_job",
      # 'elasticsearch',
      'ethon',
      'excon',
      'faraday',
      'grape',
      'graphql',
      'graphql_unified_trace_patcher',
      'graphql_trace_patcher',
      'graphql_tracing_patcher',
      'grpc',
      # 'http',
      'httpclient',
      'httprb',
      'kafka',
      'lograge',
      # "mongodb",
      # "mysql2",
      # "opensearch",
      'pg',
      # "presto",
      'que',
      'racecar',
      'rack',
      'rake',
      'resque',
      'rest_client',
      'roda',
      'semantic_logger',
      # 'sequel',
      'shoryuken',
      'sidekiq',
      'sneakers',
      'stripe',
      'sucker_punch',
      'suite',
      # "trilogy",
      # "rails",
      'railsautoinstrument',
      'railsdisableenv',
      'railsredis_activesupport',
      'railsactivejob',
      'railssemanticlogger',
      # "rails_old_redis",
      # 'action_cable',
      'action_mailer',
      'railsredis',
      'hanami',
      'hanami_autoinstrument',
      'sinatra',
      'redis',
      # 'appsec:active_record',
      'appsec:rack',
      # "appsec:integration",
      'appsec:sinatra',
      'appsec:devise',
      # "appsec:rails",
      'appsec:graphql',
      # "di:active_record"
    ]

    remainders = matrix.keys - candidates

    raise 'No remainder found. Use the matrix directly (without candidate filtering).' if remainders.empty?

    matrix = matrix.slice(*candidates)

    ruby_version = RUBY_VERSION[0..2]
    major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments
    ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"

    matching_tasks = []

    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = if RUBY_PLATFORM == 'java'
                    rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
                  else
                    rubies.include?("✅ #{ruby_version}")
                  end

        next unless matched

        gemfile = AppraisalConversion.to_bundle_gemfile(group) rescue 'Gemfile'

        matching_tasks << {
          group: group,
          gemfile: gemfile,
          task: key
        }
      end
    end

    matching_tasks.shuffle!

    # Calculate tasks per job (rounded up)
    jobs_per_runtime = 4
    jobs_per_runtime *= 2 if RUBY_PLATFORM == 'java'
    tasks_per_job = (matching_tasks.size.to_f / jobs_per_runtime).ceil


    # Create batched matrix
    batched_matrix = { 'include' => [] }

    # Distribute tasks across jobs
    matching_tasks.each_slice(tasks_per_job).with_index do |task_group, index|
      batched_matrix['include'] << {
        'batch' => index.to_s,
        'tasks' => task_group
      }
    end

    # Output the JSON
    puts JSON.dump(batched_matrix)
  end

  desc 'Run a batch of tests from JSON input'
  task :run_batch_tests do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      puts "Running task #{task['task']} (#{task['group']}) with #{task['gemfile']}"

      env = { 'BUNDLE_GEMFILE' => task['gemfile'] }

      Bundler.with_unbundled_env do
        sh(env, "bundle check || bundle install && bundle exec rake spec:#{task['task']}")
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
