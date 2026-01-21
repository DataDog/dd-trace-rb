require 'json'
require_relative 'appraisal_conversion'

# Tasks to support GitHub workflows
# rubocop:disable Metrics/BlockLength
namespace :github do
  # Distribute {file:Matrixfile} tests into batches
  task :generate_batches do
    matrix = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval

    # TODO: Tasks with sidecar service dependencies, currently all bundled together in the `build-test-misc` job.
    # TODO: Find a way to describe those service dependencies declaratively (e.g. in the Matrixfile).
    misc_candidates = [
      'mongodb',
      'elasticsearch',
      'opensearch',
      'presto',
      'dalli',
    ]

    ruby_version = RUBY_VERSION[0..2]

    matching_tasks = []
    misc_tasks = []

    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end

        next unless matched

        gemfile = begin
          AppraisalConversion.to_bundle_gemfile(group)
        rescue
          'Gemfile'
        end

        task = {task: key, group: group, gemfile: gemfile}

        if misc_candidates.include?(key)
          misc_tasks << task
        else
          matching_tasks << task
        end
      end
    end

    # Seed
    rng = (ENV['CI_TEST_SEED'] && ENV['CI_TEST_SEED'] != '') ? Random.new(ENV['CI_TEST_SEED'].to_i) : Random.new
    matching_tasks.shuffle!(random: rng)

    batch_count = 7
    batch_count *= 2 if RUBY_PLATFORM == 'java'

    tasks_per_job = (matching_tasks.size.to_f / batch_count).ceil

    batched_matrix = {'include' => []}

    matching_tasks.each_slice(tasks_per_job).with_index do |task_group, index|
      batched_matrix['include'] << {'batch' => index.to_s, 'tasks' => task_group}
    end

    data = {
      seed: rng.seed,
      batches: batched_matrix,
      misc: {'include' => [{'batch' => "0", 'tasks' => misc_tasks}]}
    }

    # Output the JSON
    puts JSON.dump(data)
  end

  task :generate_batch_summary do
    batches_json = ENV['batches_json']
    raise 'batches_json environment variable not set' unless batches_json

    data = JSON.parse(batches_json)
    summary = ENV['GITHUB_STEP_SUMMARY']

    File.open(summary, 'a') do |f|
      f.puts "*__Seed__: #{ENV["CI_TEST_SEED"]}*"
      data['include'].each do |batch|
        rows = batch['tasks'].map do |t|
          "* #{t["task"]} (#{t["group"]})"
        end

        f.puts <<~SUMMARY
          <details>
          <summary>Batch #{batch["batch"]} (#{batch["tasks"].length} tasks)</summary>

          #{rows.join("\n")}
          </details>
        SUMMARY
      end
    end
  end

  task :run_batch_build do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    tasks.each do |task|
      env = {'BUNDLE_GEMFILE' => task['gemfile']}
      cmd = 'bundle check || bundle install'
      # This retry mechanism is a generic way to improve the reliability in Github Actions,
      # since network issues can cause the `bundle install` command to fail,
      # even when Bundler has been configured to retry
      #
      # Furthermore, for JRuby 9.2, `bundle install` command failed ocassionally with the NameError.
      #
      # Mitigate the flakiness by retrying the command up to 3 times.
      #
      # https://github.com/jruby/jruby/issues/7508
      # https://github.com/jruby/jruby/issues/3656
      AppraisalConversion.with_retry do
        Bundler.with_unbundled_env { sh(env, cmd) }
      end
    end
  end

  task :run_batch_tests do
    tasks = JSON.parse(ENV['BATCHED_TASKS'] || {})

    rng = Random.new(ENV['CI_TEST_SEED'].to_i)

    tasks.each do |task|
      env = {'BUNDLE_GEMFILE' => task['gemfile']}
      cmd = "bundle exec rake spec:#{task["task"]}'[--seed #{rng.rand(0xFFFF)}]'"

      Bundler.with_unbundled_env { sh(env, cmd) }
    end
  end
end
# rubocop:enable Metrics/BlockLength
