# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/environment/execution'
require 'open3'

RSpec.describe Datadog::Core::Environment::Execution do
  around do |example|
    WebMock.enable!
    example.run
    WebMock.disable!
  end

  describe '.development?' do
    subject(:development?) { described_class.development? }

    before do
      WebMock.disable!
    end

    context 'when in an RSpec test' do
      it { is_expected.to eq(true) }
    end

    context 'when not in an RSpec test' do
      # RSpec is detected through the $PROGRAM_NAME.
      # Changing it will make RSpec detection to return false.
      #
      # We change the $PROGRAM_NAME instead of stubbing
      # `Datadog::Core::Environment::Execution.rspec?` because
      # otherwise we'll have no real test for non-RSpec cases.
      around do |example|
        begin
          original = $PROGRAM_NAME
          $PROGRAM_NAME = 'not-rspec'
          example.run
        ensure
          $PROGRAM_NAME = original
        end
      end

      let!(:repl_script) do
        lib = File.expand_path('lib')
        <<-RUBY
          # Load the working directory version of `datadog`
          $LOAD_PATH.unshift("#{lib}") unless $LOAD_PATH.include?("#{lib}")
          require 'datadog/core/environment/execution'

          # Print actual value to STDERR, as STDOUT tends to have more noise in REPL sessions.
          STDERR.print "ACTUAL:\#{Datadog::Core::Environment::Execution.development?}"
        RUBY
      end

      it 'ensure RSpec detection returns false' do
        is_expected.to eq(false)
      end

      context 'when in an IRB session' do
        it 'returns true' do
          # Ruby 2.6 does not have irb by default in a bundle, but has it outside of it.
          _, err, = Bundler.with_unbundled_env do
            Open3.capture3('irb', '--noprompt', '--noverbose', '--noecho', stdin_data: repl_script)
          end
          expect(err).to end_with('ACTUAL:true')
        end
      end

      context 'when in a Pry session' do
        it 'returns true' do
          Tempfile.create('test') do |f|
            f.write(repl_script)
            f.close

            _, err, = Open3.capture3('pry', '-f', '--noprompt', f.path)
            expect(err).to end_with('ACTUAL:true')
          end
        end
      end

      context 'when in a Minitest test' do
        before { skip('Minitest not in bundle') unless Gem.loaded_specs['minitest'] }

        it 'returns true' do
          expect_in_fork do
            # Minitest reads CLI arguments, but the current process has RSpec
            # arguments that are not relevant (nor compatible) with Minitest.
            # This happens inside a fork, thus we don't have to reset it.
            Object.const_set('ARGV', [])

            require 'minitest/autorun'

            # MiniTest 5.22.1 requires a test to be defined, otherwise it will fail
            # https://github.com/minitest/minitest/blob/master/History.rdoc#label-5.22.1+-2F+2024-02-06
            Class.new(Minitest::Test) do
              def test_it_does_something_useful
                assert true
              end
            end

            is_expected.to eq(true)
          end
        end
      end

      context 'when in a Rails Spring process' do
        before do
          unless PlatformHelpers.ci? || Gem.loaded_specs['spring']
            skip('spring gem not present. In CI, this test is never skipped.')
          end
        end

        let(:script) do
          <<-RUBY
            require 'bundler/inline'

            gemfile(true) do
              source 'https://rubygems.org'
              gem 'spring', '>= 2.0.2'
            end

            # Load the `bin/spring` file, just like a real Spring application would.
            # https://github.com/rails/spring/blob/0a80019e1abdedb3291afb13e8cfb72f3992da90/bin/spring
            ARGV = ['help'] # Let's ask for a simple Spring command, so that it returns quickly.
            load Gem.bin_path('spring', 'spring')

            #{repl_script}
          RUBY
        end

        it 'returns true' do
          _, err, = Open3.capture3('ruby', stdin_data: script)
          expect(err).to end_with('ACTUAL:true')
        end
      end

      context 'for Rails' do
        context 'not loaded' do
          it { is_expected.to eq(false) }
        end

        context 'with environment' do
          before { stub_const('Rails', rails) }
          let(:rails) { double('Rails', env: env) }

          context 'development' do
            let(:env) { 'development' }
            it { is_expected.to eq(true) }
          end

          context 'test' do
            let(:env) { 'test' }
            it { is_expected.to eq(true) }
          end

          context 'production' do
            let(:env) { 'production' }
            it { is_expected.to eq(false) }
          end
        end
      end

      context 'for Cucumber' do
        before do
          unless PlatformHelpers.ci? || Gem.loaded_specs['cucumber']
            skip('cucumber gem not present. In CI, this test is never skipped.')
          end
        end

        let(:script) do
          <<-'RUBY'
            require 'bundler/inline'

            gemfile(true) do
              source 'https://rubygems.org'
              if RUBY_VERSION >= '3.4'
                # Cucumber is broken on Ruby 3.4, requires the fix in
                # https://github.com/cucumber/cucumber-ruby/pull/1757
                gem 'cucumber', '>= 3', git: 'https://github.com/cucumber/cucumber-ruby'
              else
                gem 'cucumber', '>= 3'
              end
            end

            load Gem.bin_path('cucumber', 'cucumber')
          RUBY
        end

        it 'returns true' do
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              Bundler.with_unbundled_env do
                FileUtils.mkdir_p('features/support')

                # Add our script to `env.rb`, which is always run before any feature is executed.
                File.write('features/support/env.rb', repl_script)

                out, err, = Bundler.with_unbundled_env do
                  Open3.capture3('ruby', stdin_data: script)
                end

                expect("--OUT.\n#{out}\n--ERR\n#{err}").to include('ACTUAL:true')
              end
            end
          end
        end
      end
    end

    context 'when webmock has enabled net-http adapter11' do
      before do
        allow(described_class).to receive(:repl?).and_return(false)
        allow(described_class).to receive(:test?).and_return(false)
        allow(described_class).to receive(:rails_development?).and_return(false)

        WebMock.enable!
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '.webmock_enabled?' do
    context 'when missing constant `WebMock::HttpLibAdapters::NetHttpAdapter`' do
      it do
        hide_const('::WebMock::HttpLibAdapters::NetHttpAdapter')
        expect(described_class).not_to be_webmock_enabled
      end
    end

    context 'when missing constant `Net::HTTP`' do
      it do
        hide_const('::Net::HTTP')
        expect(described_class).not_to be_webmock_enabled
      end
    end

    context 'when `WebMock::HttpLibAdapters::NetHttpAdapter` and `Net::HTTP` constants both exist' do
      it do
        WebMock.enable!

        expect(described_class).to be_webmock_enabled
      end

      it do
        WebMock.enable!(except: [:net_http])

        expect(described_class).not_to be_webmock_enabled
      end

      it do
        WebMock.disable!

        expect(described_class).not_to be_webmock_enabled
      end

      it do
        WebMock.disable!(except: [:net_http])

        expect(described_class).to be_webmock_enabled
      end
    end

    context 'when given WebMock', skip: Gem::Version.new(Bundler::VERSION) < Gem::Version.new('2') do
      it do
        out, = Bundler.with_unbundled_env do
          Open3.capture3('ruby', stdin_data: <<-RUBY
            require 'bundler/inline'

            gemfile(true, quiet: true) do
              source 'https://rubygems.org'
              gem 'webmock'
            end

            require 'webmock'
            WebMock.enable!

            lib = File.expand_path('lib', __dir__)
            $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
            require 'datadog/core/environment/execution'

            STDOUT.print "ACTUAL:\#{Datadog::Core::Environment::Execution.webmock_enabled?}"
          RUBY
          )
        end

        expect(out).to end_with('ACTUAL:true')
      end
    end
  end
end
