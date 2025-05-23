DATADOG_PATH = File.expand_path('..', __dir__)
TMP_DIR = File.join(DATADOG_PATH, 'tmp')
BASE_CLONE_DIR = "#{TMP_DIR}/upstream/"

desc "Run instrumented gems' original test suites with datadog enabled"
namespace :upstream do
  # Executes block in the context of a GitHub repository
  def with_repository(user, repository, commit, setup = nil)
    dir = File.join(BASE_CLONE_DIR,"#{repository}-#{commit}")
    unless File.exist?(dir)
      mkdir_p(BASE_CLONE_DIR)
      sh "curl -sL https://github.com/#{user}/#{repository}/archive/#{commit}.tar.gz | tar xz -C #{BASE_CLONE_DIR}"

      Dir.chdir(dir) do
        # Ensure our bundler environment doesn't conflict
        # with the repository's environment.
        Bundler.with_unbundled_env do
          # One-time setup operations for a cloned repository
          setup.call if setup
        end
      end
    end

    Dir.chdir(dir) do
      # Ensure our bundler environment doesn't conflict
      # with the repository's environment.
      Bundler.with_unbundled_env do
        yield
      end
    end
  end

  # Install this `datadog` repository into the cloned project.
  def add_datadog_to_gemfile(path)
    File.write(path, <<-GEMFILE, mode: 'a+')
      gem 'datadog', path: '#{Pathname.new(DATADOG_PATH).relative_path_from(Dir.pwd).to_s}'
    GEMFILE
  end

  # OpenTelemetry Ruby
  # https://github.com/open-telemetry/opentelemetry-ruby
  namespace :opentelemetry do
    OTEL_GIT_COMMIT = '48eb8367c2eee15cc59d4f83ee137a9b931695fc'

    require 'climate_control'

    # One-time setup
    setup = ->() do
      Dir.chdir('api') do
        add_datadog_to_gemfile('Gemfile')

        File.write('test/test_helper.rb', <<-RUBY, mode: 'a+')
          require 'datadog'
          require 'datadog/opentelemetry'
        RUBY

        sh 'bundle install'
      end

      Dir.chdir('sdk') do
        add_datadog_to_gemfile('Gemfile')

        File.write('test/test_helper.rb', <<-RUBY, mode: 'a+')
          require 'datadog'
          require 'datadog/opentelemetry'
        RUBY

        sh 'bundle install'
      end
    end

    def skipped_tests_opt(example_names)
      skipped_tests = example_names.map{|example| Regexp.escape(example)}.join('|')
      skipped_tests.empty? ? '' : "-e='/(#{skipped_tests})/'"
    end

    desc "Run opentelemetry-api tests with datadog enabled"
    task :api do
      skipped_tests = [
        'finishes the new span at the end of the block', # Mocked OTel Span errors when datadog invokes required methods
      ]
      with_repository('open-telemetry', 'opentelemetry-ruby', OTEL_GIT_COMMIT, setup) do
        Dir.chdir('api') do
          ClimateControl.modify('TESTOPTS' => skipped_tests_opt(skipped_tests)) do
            sh 'bundle exec rake test'
          end
        end
      end
    end

    desc "Run opentelemetry-sdk tests with datadog enabled"
    task :sdk do
      skipped_tests = [
        'defaults to trace context and baggage', # The defaults are now Datadog-specific defaults
        'returns a logger instance', # The logger is now `Datadog.logger`, not the original OTel logger instance
        'warns if called more than once', # Test mocks `OpenTelemetry.logger`, which we override

        # OTel Span processor is not supported currently
        'warns on unsupported otlp transport protocol http/json',
        'warns on unsupported otlp transport protocol grpc',
        'defaults to no processors if no valid exporter is available',
        'catches and logs exporter exceptions in #on_finish',

        # Propagation configuration is overridden by Datadog
        'defaults to no processors if no valid exporter is available',
        'defaults to noop with invalid env var',
        'is user settable',
        'supports "none" as an environment variable',
        'can be set by environment variable',
        'accepts "console" as an environment variable value',
        'accepts comma separated list as an environment variable',
        'can be set by environment variable',
        'accepts "none" as an environment variable value',
        'accepts comma separated list with preceeding or trailing spaces as an environment variable',
      ]


      with_repository('open-telemetry', 'opentelemetry-ruby', OTEL_GIT_COMMIT, setup) do
        Dir.chdir('sdk') do
          ClimateControl.modify('TESTOPTS' => skipped_tests_opt(skipped_tests)) do\
            sh 'bundle exec rake test'
          end
        end
      end
    end
  end

  task opentelemetry: ['opentelemetry:api', 'opentelemetry:sdk']

  desc "Removes cloned files of instrumented gems"
  task :clean do
    FileUtils.rm_r(BASE_CLONE_DIR)
  end
end

task upstream: ['upstream:opentelemetry']
