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
          'lockfile_artifact' => "lockfile-#{runtime_alias}-${{ github.run_id }}",
          'bundle_artifact' => "bundle-#{runtime_alias}-${{ github.run_id }}",
          'dependencies_artifact' => "bundled-dependencies-#{runtime_alias}-${{ matrix.batch }}-${{ github.run_id }}",
          'cache_key' => "${{ github.ref }}-#{runtime_alias}-${{ hashFiles('*.lock') }}-${{ hashFiles('gemfiles/*.lock') }}"
        )
      end

      jobs = {}

      runtimes.each do |runtime|
        jobs[runtime.batch_id] = {
          'runs-on' => ubuntu,
          'name' => "Batch #{runtime.engine}-#{runtime.version}",
          'outputs' => {
            "#{runtime.alias}-batches" => "${{ steps.set-batches.outputs.#{runtime.alias}-batches }}"
          },
          'container' => runtime.image,
          'steps' => [
            { 'uses' => 'actions/checkout@v4' },
            { 'run' => 'bundle lock' },
            {
              'uses' => 'actions/upload-artifact@v4',
              'with' => {
                'name' => runtime.lockfile_artifact,
                'path' => '*.lock'
              }
            },
            { 'run' => 'bundle install' },
            {
              'id' => 'set-batches',
              'run' => <<~BASH
                batches_json=$(bundle exec rake github:generate_batches)
                echo "$batches_json" | ruby -rjson -e 'puts JSON.pretty_generate(JSON.parse(STDIN.read))'
                echo "#{runtime.alias}-batches=$batches_json" >> $GITHUB_OUTPUT
              BASH
            },
            {
              'uses' => 'actions/upload-artifact@v4',
              'with' => {
                'name' => runtime.bundle_artifact,
                'path' => '/usr/local/bundle'
              }
            },
          ]
        }

        jobs[runtime.build_id] = {
          'needs' => [runtime.batch_id],
          'runs-on' => ubuntu,
          'name' => "Build #{runtime.engine}-#{runtime.version}[${{ matrix.batch }}]",
          'env' => { 'BATCHED_TASKS' => '${{ toJSON(matrix.tasks) }}' },
          'strategy' => {
            'fail-fast' => false,
            'matrix' => {
              'include' => "${{ fromJson(needs.#{runtime.batch_id}.outputs.#{runtime.alias}-batches).include }}"
            }
          },
          'outputs' => {
            "#{runtime.alias}-batches" => "${{ steps.set-batches.outputs.#{runtime.alias}-batches }}"
          },
          'container' => runtime.image,
          'steps' => [
            { 'uses' => 'actions/checkout@v4' },
            {
              'uses' => 'actions/download-artifact@v4',
              'with' => {
                'name' => runtime.lockfile_artifact,
              }
            },
            {
              'uses' => 'actions/download-artifact@v4',
              'with' => {
                'name' => runtime.bundle_artifact,
                'path' => '/usr/local/bundle',
              }
            },
            { 'run' => 'bundle check && bundle exec rake github:run_batch_build' },
            {
              'uses' => 'actions/upload-artifact@v4',
              'with' => {
                'name' => runtime.dependencies_artifact,
                'path' => '/usr/local/bundle'
              }
            },
          ]
        }

        jobs[runtime.test_id] = {
          'needs' => [
            runtime.batch_id,
            runtime.build_id,
          ],
          'runs-on' => ubuntu,
          'name' => "Test #{runtime.engine}-#{runtime.version}[${{ matrix.batch }}]",
          'env' => { 'BATCHED_TASKS' => '${{ toJSON(matrix.tasks) }}' },
          'strategy' => {
            'fail-fast' => false,
            'matrix' => {
              'include' => "${{ fromJson(needs.#{runtime.batch_id}.outputs.#{runtime.alias}-batches).include }}"
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
            { 'run' => 'bundle check' },
            {
              'name' => 'Run batched tests',
              'run' => 'bundle exec rake github:run_batch_tests',
              'timeout-minutes' => 30,
            },
            {
              'if' => "${{ failure() && env.RUNNER_DEBUG == '1' }}",
              'uses' => 'mxschmitt/action-tmate@v3',
              'with' => {
                'limit-access-to-actor' => true,
              }
            }
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
        'jobs' => jobs.merge(
          'aggregate' => {
            'runs-on' => ubuntu,
            'needs' => runtimes.map(&:test_id),
            'steps' => [
              'run' => 'echo "DONE!"'
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

    batch_count = 7
    batch_count *= 2 if RUBY_PLATFORM == 'java'

    groups = []
    objects = matching_tasks.shuffle
    remaining = objects.dup

    while remaining.any?
      group = Set.new
      queue = [remaining.first]

      # Use BFS to find all connected objects
      while queue.any?
        current = queue.shift
        next if group.include?(current)

        group.add(current)

        # Find all objects that share the same task or gemfile
        connected = remaining.select do |obj|
          next if group.include?(obj)

          obj[:task] == current[:task] || obj[:gemfile] == current[:gemfile]
        end

        queue.concat(connected)
      end

      # Add the connected group and remove its objects from remaining
      groups << group.to_a
      remaining.reject! { |obj| group.include?(obj) }
    end

    # Sort groups by size in descending order
    groups.sort_by!(&:size).reverse!

    # Initialize batches
    batches = Array.new(batch_count) { [] }

    # Distribute groups to minimize size differences between batches
    groups.each do |g|
      # Find the batch with the minimum current size
      target_batch = batches.min_by(&:size)
      target_batch.concat(g)
    end

    # Create the final structure
    batched_matrix = {
      'include' => batches.map.with_index do |tasks, index|
        { 'batch' => index, 'tasks' => tasks }
      end
    }

    # Output the JSON
    puts JSON.dump(batched_matrix)
  end

  task :run_batch_build do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      env = { 'BUNDLE_GEMFILE' => task['gemfile'] }
      cmd = 'bundle check || bundle install'
      Bundler.with_unbundled_env { sh(env, cmd) }
    end
  end

  task :run_batch_tests => :run_batch_build do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      env = { 'BUNDLE_GEMFILE' => task['gemfile'] }
      cmd = "bundle exec rake spec:#{task['task']}"

      Bundler.with_unbundled_env { sh(env, cmd) }
    end
  end
end
# rubocop:enable Metrics/BlockLength
