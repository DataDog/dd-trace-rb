require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails Log Auto Injection' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    { '/logging' => 'logging_test#index' }
  end
  # defined in rails support apps
  let(:logs) { log_output.string }

  let(:log_entries) do
    logs.split("\n")
  end

  let(:controllers) do
    [logging_test_controller]
  end

  let(:logging_test_controller) do
    stub_const(
      'LoggingTestController',
      Class.new(ActionController::Base) do
        def index
          # subscribers = ::ActiveSupport::Notifications.notifier.instance_variable_get(:@subscribers)
          # puts "--------------------------------------"
          # puts "subscribers size: #{subscribers.length}"
          # puts "--------------------------------------"
          # puts subscribers.map { |s| s.instance_variable_get(:@pattern) }

          # listeners = ::ActiveSupport::Notifications.notifier.instance_variable_get(:@listeners_for)
          # puts "--------------------------------------"
          # puts "listeners_for size: #{listeners.length}"
          # puts "--------------------------------------"
          # puts listeners.keys

          # render_template.action_view
          # !render_template.action_view

          # This should be interchangeable with
          # `logger.info 'MY VOICE SHALL BE HEARD!'`
          #
          # However, in Rails 5 without TaggedLogging, logger != ::Rails.logger
          #
          # To Debug:
          # puts "Lograge Logger: #{::Lograge.logger && ::Lograge.logger.object_id}"
          # puts "logger: #{logger.object_id}"
          # puts "Rails.logger: #{::Rails.logger.object_id}"
          ::Rails.logger.info 'MY VOICE SHALL BE HEARD!'

          if ::Rails.version >= '4'
            render plain: 'OK'
          else
            render inline: 'OK'
          end
        end
      end
    )
  end

  before do
    Datadog.configuration.tracing[:rails].reset_options!

    Datadog.configure do |c|
      c.tracing.instrument :rails
      c.tracing.log_injection = log_injection
    end

    allow(ENV).to receive(:[]).and_call_original
  end

  after do
    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configuration.tracing[:lograge].reset_options!
  end

  subject(:response) do
    get '/logging'
  end

  context 'with log injection enabled' do
    let(:log_injection) { true }

    context 'with default Ruby logger' do
      it 'does not contain trace id' do
        is_expected.to be_ok

        expect(logs).to_not be_empty
        # From `Rails::Rack::Logger`
        expect(log_entries).to have(2).items
        rack_rails_logger_entry, my_entry = log_entries

        expect(rack_rails_logger_entry).not_to include trace.id.to_s

        expect(my_entry).not_to include trace.id.to_s
      end
    end

    context 'with Tagged Logging' do
      let(:logger) do
        ::ActiveSupport::TaggedLogging.new(super())
      end

      context 'with Tagged logging setup and no tags' do
        it 'injects trace_id into logs' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          # From `Rails::Rack::Logger`
          expect(log_entries).to have(2).items
          rack_rails_logger_entry, my_entry = log_entries

          expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"

          expect(my_entry).to include trace.id.to_s
        end
      end

      context 'with tagged logging setup and existing log_tags' do
        let(:log_tags) do
          %w[some_info some_other_info]
        end

        it 'injects trace_id into logs and preserve existing log tags' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          # From `Rails::Rack::Logger`
          expect(log_entries).to have(2).items
          rack_rails_logger_entry, my_entry = log_entries

          expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"
          expect(rack_rails_logger_entry).to include '[some_info]'
          expect(rack_rails_logger_entry).to include '[some_other_info]'

          expect(my_entry).to include trace.id.to_s
          expect(my_entry).to include '[some_info]'
          expect(my_entry).to include '[some_other_info]'
        end
      end
    end

    if Rails.version >= '4'
      context 'with Lograge' do
        # for log_injection testing
        require 'lograge'

        let(:lograge_options) do
          { enabled?: true }
        end

        context 'with lograge enabled' do
          context 'with Lograge setup and no custom_options' do
            it 'injects trace_id into logs' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).to include trace.id.to_s
              expect(controller_logger_entry).to include 'ddsource=ruby'

              expect(my_entry).not_to include trace.id.to_s
            end
          end

          context 'with Lograge and existing custom_options as a hash' do
            let(:lograge_options) do
              super().merge(
                custom_options: {
                  'some_hash_info' => 'test_hash_value',
                  'some_other_hash_info' => 'other_test_hash_value'
                }
              )
            end

            it 'injects trace_id into logs and preserve existing hash' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).to include trace.id.to_s
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include 'some_hash_info=test_hash_value'
              expect(controller_logger_entry).to include 'some_other_hash_info=other_test_hash_value'

              expect(my_entry).not_to include trace.id.to_s
            end
          end

          context 'with Lograge and existing custom_options as a lambda' do
            let(:lograge_options) do
              super().merge(
                custom_options: lambda do |_event|
                  {
                    'some_lambda_info' => 'test_lambda_value',
                    'some_other_lambda_info' => 'other_test_lambda_value'
                  }
                end
              )
            end

            it 'injects trace_id into logs and preserve existing lambda' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).to include trace.id.to_s
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include 'some_lambda_info=test_lambda_value'
              expect(controller_logger_entry).to include 'some_other_lambda_info=other_test_lambda_value'

              expect(my_entry).not_to include trace.id.to_s
            end
          end
        end

        context 'with lograge disabled' do
          before do
            Datadog.configuration.tracing[:lograge].enabled = false
          end

          it 'does not inject trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(3).items

            rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

            expect(rack_rails_logger_entry).not_to include trace.id.to_s

            expect(my_entry).not_to include trace.id.to_s

            expect(controller_logger_entry).not_to include trace.id.to_s
          end
        end
      end

      context 'with Tagged Logging and Lograge' do
        # for log_injection testing
        require 'lograge'

        let(:logger) do
          ::ActiveSupport::TaggedLogging.new(super())
        end

        let(:lograge_options) do
          { enabled?: true }
        end

        context 'with lograge and tagged logging enabled' do
          context 'with no custom_options' do
            it 'injects trace_id into logs' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"

              expect(my_entry).to include "dd.trace_id=#{trace.id}"

              expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
              expect(controller_logger_entry).to include 'ddsource=ruby'
            end
          end

          context 'with tagged logging setup and existing log_tags' do
            let(:log_tags) { %w[some_info some_other_info] }

            it 'injects trace_id into logs and preserve existing log tags' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"
              expect(rack_rails_logger_entry).to include '[some_info]'
              expect(rack_rails_logger_entry).to include '[some_other_info]'

              expect(my_entry).to include "dd.trace_id=#{trace.id}"
              expect(my_entry).to include '[some_info]'
              expect(my_entry).to include '[some_other_info]'

              expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include '[some_info]'
              expect(controller_logger_entry).to include '[some_other_info]'
            end
          end

          context 'with Lograge and existing custom_options as a hash' do
            let(:lograge_options) do
              super().merge(
                custom_options: {
                  'some_hash_info' => 'test_hash_value',
                  'some_other_hash_info' => 'other_test_hash_value'
                }
              )
            end

            it 'injects trace_id into logs and preserve existing hash' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"

              expect(my_entry).to include "dd.trace_id=#{trace.id}"

              expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include 'some_hash_info=test_hash_value'
              expect(controller_logger_entry).to include 'some_other_hash_info=other_test_hash_value'
            end
          end

          context 'with Lograge and existing custom_options as a lambda' do
            let(:lograge_options) do
              super().merge(
                custom_options: lambda do |_event|
                  {
                    'some_lambda_info' => 'test_lambda_value',
                    'some_other_lambda_info' => 'other_test_lambda_value'
                  }
                end
              )
            end

            it 'injects trace_id into logs and preserve existing lambda' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"

              expect(my_entry).to include "dd.trace_id=#{trace.id}"

              expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include 'some_lambda_info=test_lambda_value'
              expect(controller_logger_entry).to include 'some_other_lambda_info=other_test_lambda_value'
            end
          end

          context 'with existing log_tags and Lograge custom_options' do
            let(:log_tags) { %w[some_info some_other_info] }

            let(:lograge_options) do
              super().merge(
                custom_options: {
                  'some_hash_info' => 'test_hash_value',
                  'some_other_hash_info' => 'other_test_hash_value'
                }
              )
            end

            it 'injects trace_id into logs' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"
              expect(rack_rails_logger_entry).to include '[some_info]'
              expect(rack_rails_logger_entry).to include '[some_other_info]'

              expect(my_entry).to include "dd.trace_id=#{trace.id}"
              expect(my_entry).to include '[some_info]'
              expect(my_entry).to include '[some_other_info]'

              expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
              expect(controller_logger_entry).to include '[some_info]'
              expect(controller_logger_entry).to include '[some_other_info]'
              expect(controller_logger_entry).to include 'ddsource=ruby'
              expect(controller_logger_entry).to include 'some_hash_info=test_hash_value'
              expect(controller_logger_entry).to include 'some_other_hash_info=other_test_hash_value'
            end
          end
        end
      end
    end
  end

  context 'with log injection disabled' do
    let(:log_injection) { false }

    context 'with default Ruby logger' do
      it 'does not contain trace id' do
        is_expected.to be_ok

        expect(logs).to_not be_empty
        # From `Rails::Rack::Logger`
        expect(log_entries).to have(2).item
        rack_rails_logger_entry, my_entry = log_entries

        expect(rack_rails_logger_entry).not_to include trace.id.to_s

        expect(my_entry).not_to include trace.id.to_s
      end
    end

    context 'with Tagged Logging' do
      let(:logger) do
        ::ActiveSupport::TaggedLogging.new(super())
      end

      context 'with Tagged logging setup and no tags' do
        it 'does not inject trace_id' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          expect(log_entries).to have(2).item

          rack_rails_logger_entry, my_entry = log_entries

          expect(rack_rails_logger_entry).not_to include trace.id.to_s

          expect(my_entry).not_to include trace.id.to_s
        end
      end

      context 'with tagged logging setup and existing log_tags' do
        let(:log_tags) { %w[some_info some_other_info] }

        it 'does not inject trace_id' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          expect(log_entries).to have(2).items

          rack_rails_logger_entry, my_entry = log_entries

          expect(rack_rails_logger_entry).not_to include trace.id.to_s
          expect(rack_rails_logger_entry).to include '[some_info]'
          expect(rack_rails_logger_entry).to include '[some_other_info]'

          expect(my_entry).not_to include trace.id.to_s
          expect(my_entry).to include '[some_info]'
          expect(my_entry).to include '[some_other_info]'
        end
      end

      context 'then enabled at runtime' do
        context 'with Tagged logging setup and no tags' do
          before do
            app # Initialize app before enabling log injection
            Datadog.configure { |c| c.tracing.log_injection = true }
          end

          it 'injects trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entry, my_entry = log_entries
            expect(rack_rails_logger_entry).to include "dd.trace_id=#{trace.id}"
            expect(my_entry).to include "dd.trace_id=#{trace.id}"
          end
        end
      end
    end

    if Rails.version >= '4'
      context 'with Lograge' do
        # for log_injection testing
        require 'lograge'

        let(:lograge_options) do
          { enabled?: true }
        end

        context 'with lograge enabled' do
          context 'with Lograge setup and no custom_options' do
            it 'does not inject trace_id' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(my_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).not_to include trace.id.to_s
            end
          end

          context 'with Lograge and existing custom_options as a hash' do
            let(:lograge_options) do
              super().merge(
                custom_options: {
                  'some_hash_info' => 'test_hash_value',
                  'some_other_hash_info' => 'other_test_hash_value'
                }
              )
            end

            it 'does not inject trace_id and preserve existing hash' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(my_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).not_to include trace.id.to_s
              expect(controller_logger_entry).to include 'some_hash_info=test_hash_value'
              expect(controller_logger_entry).to include 'some_other_hash_info=other_test_hash_value'
            end
          end

          context 'with Lograge and existing custom_options as a lambda' do
            let(:lograge_options) do
              super().merge(
                custom_options: lambda do |_event|
                  {
                    'some_lambda_info' => 'test_lambda_value',
                    'some_other_lambda_info' => 'other_test_lambda_value'
                  }
                end
              )
            end

            it 'does not inject trace_id and preserve existing lambda' do
              is_expected.to be_ok

              expect(logs).to_not be_empty
              expect(log_entries).to have(3).items

              rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

              expect(rack_rails_logger_entry).not_to include trace.id.to_s

              expect(my_entry).not_to include trace.id.to_s

              expect(controller_logger_entry).not_to include trace.id.to_s
              expect(controller_logger_entry).to include 'some_lambda_info=test_lambda_value'
              expect(controller_logger_entry).to include 'some_other_lambda_info=other_test_lambda_value'
            end
          end
        end

        context 'with lograge disabled' do
          before do
            Datadog.configuration.tracing[:lograge].enabled = false
          end

          it 'does not inject trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(3).items

            rack_rails_logger_entry, my_entry, controller_logger_entry = log_entries

            expect(rack_rails_logger_entry).not_to include trace.id.to_s

            expect(my_entry).not_to include trace.id.to_s

            expect(controller_logger_entry).not_to include trace.id.to_s
          end
        end
      end
    end
  end
end
