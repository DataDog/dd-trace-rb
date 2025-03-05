require 'json'
require_relative 'appraisal_conversion'

# rubocop:disable Metrics/BlockLength
namespace :github do
  task :generate_batches do
    matrix = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval

    # TODO: These are the execptions, find a way to describe those service dependencies in CI using a more generic mechansim.
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

        gemfile = AppraisalConversion.to_bundle_gemfile(group) rescue 'Gemfile'

        task = { task: key, group: group, gemfile: gemfile }

        if misc_candidates.include?(key)
          misc_tasks << task
        else
          matching_tasks << task
        end
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

    data = {
      batches: batched_matrix,
      misc: { 'include' => [ { 'batch' => "0", 'tasks' => misc_tasks } ] }
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
      with_retry do
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
