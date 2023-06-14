require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails Log Auto Injection' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    { '/logging' => 'logging_test#index' }
  end

  let(:controllers) do
    [logging_test_controller]
  end

  let(:logging_test_controller) do
    stub_const(
      'LoggingTestController',
      Class.new(ActionController::Base) do
        def index
          # logger.info "yo"
          render plain: "OK"
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

  # defined in rails support apps
  let(:logs) { log_output.string }
  let(:log_entries) { logs.split("\n") }

  subject(:response) { get '/logging' }

  context 'with log injection enabled' do
    let(:log_injection) { true }

    context 'with Tagged Logging' do
      before do
        allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return(true)
      end

      context 'with Tagged logging setup and no tags' do
        it 'injects trace_id into logs' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          # From `Rails::Rack::Logger`
          expect(log_entries).to have(1).item
          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"
        end
      end

      context 'with tagged logging setup and existing log_tags' do
        before do
          allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
        end

        it 'injects trace_id into logs and preserve existing log tags' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          # From `Rails::Rack::Logger`
          expect(log_entries).to have(1).item
          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"
          expect(rack_rails_logger_entries).to include "[some_info]"
          expect(rack_rails_logger_entries).to include "[some_other_info]"
        end
      end
    end

    context 'with Lograge', skip: Rails.version < '4' do
      # for log_injection testing
      require 'lograge'

      context 'with lograge enabled' do
        before do
          allow(ENV).to receive(:[]).with('USE_LOGRAGE').and_return(true)
        end

        context 'with Lograge setup and no custom_options' do
          it 'injects trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).to include trace.id.to_s
            expect(controller_logger_entry).to include "ddsource=ruby"
          end
        end

        context 'with Lograge and existing custom_options as a hash' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              'some_hash_info' => 'test_hash_value',
              'some_other_hash_info' => 'other_test_hash_value'
            )
          end

          it 'injects trace_id into logs and preserve existing hash' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).to include trace.id.to_s
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "some_hash_info=test_hash_value"
            expect(controller_logger_entry).to include "some_other_hash_info=other_test_hash_value"
          end
        end

        context 'with Lograge and existing custom_options as a lambda' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              lambda do |_event|
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
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).to include "#{trace.id}"
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "some_lambda_info=test_lambda_value"
            expect(controller_logger_entry).to include "some_other_lambda_info=other_test_lambda_value"
          end
        end
      end

      context 'with lograge disabled' do
        it 'does not inject trace_id into logs' do
          is_expected.to be_ok

          expect(logs).to_not be_empty

          expect(log_entries).to have(1).item

          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).not_to include trace.id.to_s
        end
      end
    end

    context 'with Tagged Logging and Lograge', skip: Rails.version < '4' do
      # for log_injection testing
      require 'lograge'

      context 'with lograge and tagged logging enabled' do
        before do
          allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return(true)
          allow(ENV).to receive(:[]).with('USE_LOGRAGE').and_return(true)
        end

        context 'with no custom_options' do
          it 'injects trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"

            expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
            expect(controller_logger_entry).to include "ddsource=ruby"
          end
        end

        context 'with tagged logging setup and existing log_tags' do
          before do
            allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
          end

          it 'injects trace_id into logs and preserve existing log tags' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"
            expect(rack_rails_logger_entries).to include "[some_info]"
            expect(rack_rails_logger_entries).to include "[some_other_info]"


            expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "[some_info]"
            expect(controller_logger_entry).to include "[some_other_info]"
          end
        end

        context 'with Lograge and existing custom_options as a hash' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              'some_hash_info' => 'test_hash_value',
              'some_other_hash_info' => 'other_test_hash_value'
            )
          end

          it 'injects trace_id into logs and preserve existing hash' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"

            expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "some_hash_info=test_hash_value"
            expect(controller_logger_entry).to include "some_other_hash_info=other_test_hash_value"
          end
        end

        context 'with Lograge and existing custom_options as a lambda' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              lambda do |_event|
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
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"

            expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "some_lambda_info=test_lambda_value"
            expect(controller_logger_entry).to include "some_other_lambda_info=other_test_lambda_value"
          end
        end

        context 'with existing log_tags and Lograge custom_options' do
          before do
            allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              'some_hash_info' => 'test_hash_value',
              'some_other_hash_info' => 'other_test_hash_value'
            )
          end

          it 'injects trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).to include "dd.trace_id=#{trace.id}"
            expect(rack_rails_logger_entries).to include "[some_info]"
            expect(rack_rails_logger_entries).to include "[some_other_info]"

            expect(controller_logger_entry.scan(trace.id.to_s)).to have(2).times
            expect(controller_logger_entry).to include "[some_info]"
            expect(controller_logger_entry).to include "[some_other_info]"
            expect(controller_logger_entry).to include "ddsource=ruby"
            expect(controller_logger_entry).to include "some_hash_info=test_hash_value"
            expect(controller_logger_entry).to include "some_other_hash_info=other_test_hash_value"
          end
        end
      end

      context 'with lograge disabled' do
        it 'does not inject trace_id into logs' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          expect(log_entries).to have(1).item

          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).not_to include trace.id.to_s
        end
      end
    end
  end

  context 'with log injection disabled' do
    let(:log_injection) { false }

    # before do
    #   # Need to disable explicity?
    #   Datadog.configuration.tracing[:lograge].enabled = false
    # end

    context 'with Tagged Logging' do
      before do
        allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return(true)
      end

      context 'with Tagged logging setup and no tags' do
        it 'does not inject trace_id' do
          is_expected.to be_ok

          expect(logs).to_not be_empty
          expect(log_entries).to have(1).item

          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).not_to include trace.id.to_s
        end
      end

      context 'with tagged logging setup and existing log_tags' do
        before do
          allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
        end

        it 'does not inject trace_id' do
          is_expected.to be_ok

          expect(logs).to_not be_empty

          expect(log_entries).to have(1).item

          rack_rails_logger_entries, = log_entries

          expect(rack_rails_logger_entries).not_to include trace.id.to_s
          expect(rack_rails_logger_entries).to include "[some_info]"
          expect(rack_rails_logger_entries).to include "[some_other_info]"
        end
      end
    end

    context 'with Lograge', skip: Rails.version < '4' do
      # for log_injection testing
      require 'lograge'

      context 'with lograge enabled' do
        before do
          allow(ENV).to receive(:[]).with('USE_LOGRAGE').and_return(true)
        end

        context 'with Lograge setup and no custom_options' do
          it 'does not inject trace_id' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).not_to include trace.id.to_s
          end
        end

        context 'with Lograge and existing custom_options as a hash' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              'some_hash_info' => 'test_hash_value',
              'some_other_hash_info' => 'other_test_hash_value'
            )
          end

          it 'does not inject trace_id and preserve existing hash' do
            is_expected.to be_ok

            expect(logs).to_not be_empty
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).not_to include trace.id.to_s
            expect(controller_logger_entry).to include "some_hash_info=test_hash_value"
            expect(controller_logger_entry).to include "some_other_hash_info=other_test_hash_value"
          end
        end

        context 'with Lograge and existing custom_options as a lambda' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              lambda do |_event|
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
            expect(log_entries).to have(2).items

            rack_rails_logger_entries, controller_logger_entry = log_entries

            expect(rack_rails_logger_entries).not_to include trace.id.to_s

            expect(controller_logger_entry).not_to include trace.id.to_s
            expect(controller_logger_entry).to include "some_lambda_info=test_lambda_value"
            expect(controller_logger_entry).to include "some_other_lambda_info=other_test_lambda_value"
          end
        end
      end
    end
  end
end
