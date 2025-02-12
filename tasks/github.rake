require 'pry'
require 'json'
require 'psych'
require 'ostruct'
require_relative 'appraisal_conversion'

# rubocop:disable Metrics/BlockLength
namespace :github do
  namespace :actions do
    task :test_template do |t|
      ubuntu = 'ubuntu-24.04'

      redis = { 'image' => 'ghcr.io/datadog/images-rb/services/redis:6.2' }
      memcached = { 'image' => 'ghcr.io/datadog/images-rb/services/memcached:1.5-alpine' }
      mongodb = { 'image' => 'ghcr.io/datadog/images-rb/services/mongo:3.6' }
      presto = { 'image' => 'ghcr.io/datadog/images-rb/services/starburstdata/presto:332-e.9' }
      mysql = {
        'image' => 'ghcr.io/datadog/images-rb/services/mysql:8.0',
        'env' => {
          'MYSQL_ROOT_PASSWORD' => 'root',
          'MYSQL_PASSWORD' => 'mysql',
          'MYSQL_USER' => 'mysql',
        }
      }
      postgres = {
        'image' => 'ghcr.io/datadog/images-rb/services/postgres:9.6',
        'env' => {
          'POSTGRES_PASSWORD' => 'postgres',
          'POSTGRES_USER' => 'postgres',
          'POSTGRES_DB' => 'postgres',
        }
      }
      elasticsearch = {
        'image' => 'ghcr.io/datadog/images-rb/services/elasticsearch:8.1.3',
        'env' => {
          'discovery.type' => 'single-node',
          'xpack.security.enabled' => 'false',
          'ES_JAVA_OPTS' => '-Xms750m -Xmx750m',
        }
      }
      opensearch = {
        'image' => 'ghcr.io/datadog/images-rb/services/opensearchproject/opensearch:2.8.0',
        'env' => {
          'discovery.type' => 'single-node',
          'DISABLE_SECURITY_PLUGIN' => 'true',
          'DISABLE_PERFORMANCE_ANALYZER_AGENT_CLI' => 'true',
          'cluster.routing.allocation.disk.watermark.low' => '3gb',
          'cluster.routing.allocation.disk.watermark.high' => '2gb',
          'cluster.routing.allocation.disk.watermark.flood_stage' => '1gb',
          'cluster.routing.allocation.disk.threshold_enabled' => 'false',
        }
      }
      # Rubocop
      agent = {
        'image' => 'ghcr.io/datadog/dd-apm-test-agent/ddapm-test-agent:v1.18.0',
        'env' => {
          'LOG_LEVEL' => 'DEBUG',
          'TRACE_LANGUAGE' => 'ruby',
          'PORT' => '9126',
          'DD_POOL_TRACE_CHECK_FAILURES' => 'true',
          'DD_DISABLE_ERROR_RESPONSES' => 'true',
          'ENABLED_CHECKS' => 'trace_content_length,trace_stall,meta_tracer_version_header,trace_count_header,trace_peer_service,trace_dd_service', # rubocop:disable Layout/LineLength
        }
      }
      runtimes = [
        'ruby:3.4',
        'ruby:3.3',
        'ruby:3.2',
        'ruby:3.1',
        'ruby:3.0',
        'ruby:2.7',
        'ruby:2.6',
        'ruby:2.5',
        'jruby:9.4',
        'jruby:9.3',
        'jruby:9.2',
      ].map do |runtime|
        engine, version = runtime.split(':')
        runtime_alias = "#{engine}-#{version.delete('.')}"

        OpenStruct.new(
          'engine' => engine,
          'version' => version,
          'alias' => runtime_alias,
          'image' => "ghcr.io/datadog/images-rb/engines/#{engine}:#{version}",
          'batch_id' => "batch-#{runtime_alias}",
          'build_id' => "build-#{runtime_alias}",
          'test_id' => "test-#{runtime_alias}",
          'build_test_id' => "build-test-#{runtime_alias}",
          'lockfile_artifact' => "lockfile-#{runtime_alias}-${{ github.run_id }}",
          'bundle_artifact' => "bundle-#{runtime_alias}-${{ github.run_id }}",
          'dependencies_artifact' => "bundled-dependencies-#{runtime_alias}-${{ matrix.batch }}-${{ github.run_id }}",
          'junit_artifact' => "junit-#{runtime_alias}-${{ matrix.batch }}-${{ github.run_id }}",
          'bundle_cache_key' => "bundle-${{ runner.os }}-${{ runner.arch }}-#{runtime_alias}-${{ hashFiles('*.lock') }}"
        )
      end

      jobs = {}

      runtimes.each do |runtime|
        jobs[runtime.batch_id] = {
          'runs-on' => ubuntu,
          'name' => "batch (#{runtime.engine}-#{runtime.version})",
          'outputs' => {
            'batches' => '${{ steps.set-batches.outputs.batches }}',
            'cache-key' => '${{ steps.restore-cache.outputs.cache-primary-key }}'
          },
          'container' => runtime.image,
          'steps' => [
            { 'uses' => 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' },
            { 'run' => 'bundle lock' },
            {
              'uses' => 'actions/upload-artifact@65c4c4a1ddee5b72f698fdd19549f0f0fb45cf08',
              'with' => {
                'name' => runtime.lockfile_artifact,
                'path' => '*.lock'
              }
            },
            {
              'uses' => 'actions/cache/restore@1bd1e32a3bdc45362d1e726936510720a7c30a57',
              'id' => 'restore-cache',
              'with' => {
                'key' => runtime.bundle_cache_key,
                'path' => '/usr/local/bundle'
              }
            },
            { 'if' => "steps.restore-cache.outputs.cache-hit != 'true'",
              'run' => 'bundle install' },
            { 'if' => "steps.restore-cache.outputs.cache-hit != 'true'",
              'uses' => 'actions/cache/save@1bd1e32a3bdc45362d1e726936510720a7c30a57',
              'with' => {
                'key' => '${{ steps.restore-cache.outputs.cache-primary-key }}',
                'path' => '/usr/local/bundle'
              } },
            {
              'id' => 'set-batches',
              'run' => <<~BASH
                batches_json=$(bundle exec rake github:generate_batches)
                echo "$batches_json" | ruby -rjson -e 'puts JSON.pretty_generate(JSON.parse(STDIN.read))'
                echo "batches=$batches_json" >> $GITHUB_OUTPUT
              BASH
            },
            {
              'env' => {
                'batches_json' => '${{ steps.set-batches.outputs.batches }}',
              },
              'run' => 'bundle exec rake github:generate_batch_summary'
            },
          ]
        }

        jobs[runtime.build_test_id] = {
          'needs' => [
            runtime.batch_id,
          ],
          'runs-on' => ubuntu,
          'name' => "build & test (#{runtime.engine}-#{runtime.version}) [${{ matrix.batch }}]",
          'env' => { 'BATCHED_TASKS' => '${{ toJSON(matrix.tasks) }}' },
          'strategy' => {
            'fail-fast' => false,
            'matrix' => {
              'include' => "${{ fromJson(needs.#{runtime.batch_id}.outputs.batches).include }}"
            }
          },
          'container' => {
            'image' => runtime.image,
            'env' => {
              'DD_INSTRUMENTATION_TELEMETRY_ENABLED' => 'false',
              'DD_REMOTE_CONFIGURATION_ENABLED' => 'false',
              'TEST_POSTGRES_HOST' => 'postgres',
              'TEST_REDIS_HOST' => 'redis',
              'TEST_ELASTICSEARCH_HOST' => 'elasticsearch',
              'TEST_MEMCACHED_HOST' => 'memcached',
              'TEST_MONGODB_HOST' => 'mongodb',
              'TEST_MYSQL_HOST' => 'mysql',
              'TEST_OPENSEARCH_HOST' => 'opensearch',
              'TEST_OPENSEARCH_PORT' => '9200',
              'TEST_PRESTO_HOST' => 'presto',
              'DD_AGENT_HOST' => 'agent',
              'DD_TRACE_AGENT_PORT' => '9126',
              'DATADOG_GEM_CI' => 'true',
              'TEST_DATADOG_INTEGRATION' => '1',
              'JRUBY_OPTS' => '--dev', # Faster JVM startup: https://github.com/jruby/jruby/wiki/Improving-startup-time#use-the---dev-flag
            }
          },
          'services' => {
            'postgres' => postgres,
            'redis' => redis,
            'elasticsearch' => elasticsearch,
            'memcached' => memcached,
            'mongodb' => mongodb,
            'opensearch' => opensearch,
            'presto' => presto,
            'mysql' => mysql,
            'agent' => agent,
          },
          'steps' => [
            { 'uses' => 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' },
            {
              'name' => 'Configure Git',
              'run' => 'git config --global --add safe.directory "$GITHUB_WORKSPACE"'
            },
            {
              'uses' => 'actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16',
              'with' => {
                'name' => runtime.lockfile_artifact,
              }
            },
            {
              'uses' => 'actions/cache/restore@1bd1e32a3bdc45362d1e726936510720a7c30a57',
              'id' => 'restore-cache',
              'with' => {
                'key' => "${{ needs.#{runtime.batch_id}.outputs.cache-key }}",
                'path' => '/usr/local/bundle'
              }
            },
            { 'run' => 'bundle check || bundle install' },
            { 'run' => 'bundle exec rake github:run_batch_build' },
            { 'run' => 'ln -s .rspec-local.example .rspec-local' },
            { 'run' => 'bundle exec rake github:run_batch_tests' },
            {
              'if' => "${{ failure() && env.RUNNER_DEBUG == '1' }}",
              'uses' => 'mxschmitt/action-tmate@e5c7151931ca95bad1c6f4190c730ecf8c7dde48',
              'with' => {
                'limit-access-to-actor' => true,
              }
            },
            {
              'if' => 'always()',
              'run' => 'ruby .github/scripts/test_agent_check.rb'
            },
            {
              'if' => 'always()',
              'uses' => 'actions/upload-artifact@65c4c4a1ddee5b72f698fdd19549f0f0fb45cf08',
              'with' => {
                'name' => runtime.junit_artifact,
                'path' => 'tmp/rspec/*.xml'
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
            ]
          },
          'pull_request' => {
            'branches' => [
              'master',
            ]
          },
          'schedule' => [
            { 'cron' => '0 */4 * * 1-5' }
          ]
        },
        'concurrency' => {
          'group' => '${{ github.workflow }}-${{ github.ref }}',
          'cancel-in-progress' => '${{ github.ref != \'refs/heads/master\' }}'
        },
        'jobs' => jobs.merge(
          'complete' => {
            'name' => 'complete',
            'runs-on' => ubuntu,
            'needs' => runtimes.map(&:build_test_id),
            'steps' => [
              'run' => 'echo "DONE!"'
            ]
          },
          'upload-junit' => {
            'name' => 'upload/junit',
            'if' => '!cancelled()',
            'runs-on' => ubuntu,
            'env' => {
              'DD_APP_KEY' => '${{ secrets.DD_APP_KEY }}',
              'DD_API_KEY' => '${{ secrets.DD_API_KEY }}',
              'DD_ENV' => 'ci',
              'DATADOG_SITE' => 'datadoghq.com',
              'DD_SERVICE' => 'dd-trace-rb',
            },
            # 'container' => {
            #   'image' => 'datadog/ci',
            #   'credentials' => {
            #     'username' => '${{ secrets.DOCKERHUB_USERNAME }}',
            #     'password' => '${{ secrets.DOCKERHUB_TOKEN }}'
            #   },
            #   'env' => {
            #     'DD_APP_KEY' => '${{ secrets.DD_APP_KEY }}',
            #     'DD_API_KEY' => '${{ secrets.DD_API_KEY }}',
            #     'DD_ENV' => 'ci',
            #     'DATADOG_SITE' => 'datadoghq.com',
            #     'DD_SERVICE' => 'dd-trace-rb',
            #   }
            # },
            'needs' => runtimes.map(&:build_test_id),
            'steps' => [
              { 'uses' => 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' },
              {
                'run' => <<~BASH
                  curl -L --fail --retry 5 https://github.com/DataDog/datadog-ci/releases/latest/download/datadog-ci_linux-x64 --output /usr/local/bin/datadog-ci
                  chmod +x /usr/local/bin/datadog-ci
                BASH
              },
              { 'run' => 'mkdir -p tmp/rspec && datadog-ci version' },
              {
                'uses' => 'actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16',
                'with' => {
                  'path' => 'tmp/rspec',
                  'pattern' => 'junit-*',
                  'merge-multiple' => true
                }
              },
              { 'run' => "sed -i 's;file=\"\.\/;file=\";g' tmp/rspec/*.xml" },
              { 'run' => 'datadog-ci junit upload --verbose --dry-run tmp/rspec/' },
            ]
          }
        )
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

    exceptions = [
      # 'sidekiq', # Connection refused - connect(2) for 127.0.0.1:6379 (RedisClient::CannotConnectError)
    ]

    # candidates = exceptions
    candidates = matrix.keys - exceptions

    raise 'No candidates.' if candidates.empty?

    matrix = matrix.slice(*candidates)

    ruby_version = RUBY_VERSION[0..2]

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

        matching_tasks << { task: key, group: group, gemfile: gemfile }
      end
    end

    # Random!
    matching_tasks.shuffle!

    batch_count = 7
    batch_count *= 2 if RUBY_PLATFORM == 'java'

    tasks_per_job = (matching_tasks.size.to_f / batch_count).ceil

    batched_matrix = { 'include' => [] }

    matching_tasks.each_slice(tasks_per_job).with_index do |task_group, index|
      batched_matrix['include'] << { 'batch' => index.to_s, 'tasks' => task_group }
    end

    # Output the JSON
    puts JSON.dump(batched_matrix)
  end

  task :generate_batch_summary do
    batches_json = ENV['batches_json']
    raise 'batches_json environment variable not set' unless batches_json

    data = JSON.parse(batches_json)
    summary = ENV['GITHUB_STEP_SUMMARY']

    File.open(summary, 'a') do |f|
      data['include'].each do |batch|
        rows = batch['tasks'].map do |t|
          "* #{t['task']} (#{t['group']})"
        end

        f.puts <<~SUMMARY
          <details>
          <summary>Batch #{batch['batch']} (#{batch['tasks'].length} tasks)</summary>

          #{rows.join("\n")}
          </details>
        SUMMARY
      end
    end
  end

  task :run_batch_build do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      env = { 'BUNDLE_GEMFILE' => task['gemfile'] }
      cmd = 'bundle check || bundle install'

      if RUBY_PLATFORM == 'java' && RUBY_ENGINE_VERSION.start_with?('9.2')
        # For JRuby 9.2, the `bundle install` command failed ocassionally with the NameError.
        #
        # Mitigate the flakiness by retrying the command up to 3 times.
        #
        # https://github.com/jruby/jruby/issues/7508
        # https://github.com/jruby/jruby/issues/3656
        with_retry do
          Bundler.with_unbundled_env { sh(env, cmd) }
        end
      else
        Bundler.with_unbundled_env { sh(env, cmd) }
      end
    end
  end

  task :run_batch_tests do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      env = { 'BUNDLE_GEMFILE' => task['gemfile'] }
      cmd = "bundle exec rake spec:#{task['task']}"

      Bundler.with_unbundled_env { sh(env, cmd) }
    end
  end

  def with_retry(&block)
    retries = 0
    begin
      yield
    rescue StandardError => e
      rake_output_message(
        "Bundle install failure (Attempt: #{retries + 1}): #{e.class.name}: #{e.message}, \
        Source:\n#{Array(e.backtrace).join("\n")}"
      )
      sleep(2**retries)
      retries += 1
      retry if retries < 3
      raise
    end
  end
end
# rubocop:enable Metrics/BlockLength
