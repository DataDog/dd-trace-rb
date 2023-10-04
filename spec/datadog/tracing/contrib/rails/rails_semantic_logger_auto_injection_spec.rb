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

  # RailsSemanticLogger `4.2.1` is the last version available for Ruby 2.2,
  # starting from `4.3.0`, uses `swap_subscriber` strategy.
  #
  # Replacing the default ones with its own.
  #   ::ActionView::LogSubscriber => ::RailsSemanticLogger::ActionView::LogSubscriber
  #
  # This request-response cycle would creates 6 log entries
  #
  # 1. Rack -- Started
  # 2. LoggingTestController -- Processing
  # 3. LoggingTestController -- MY VOICE SHALL BE HEARD
  # 4. ActionView -- Rendering
  # 5. ActionView -- Rendered
  # 6. LoggingTestController -- Completed
  #
  # Before RailsSemanticLogger `4.3.0` or Before Rails `5` it would creates 5 log entries
  #
  # 1. Rack -- Started
  # 2. LoggingTestController -- Processing
  # 3. LoggingTestController -- MY VOICE SHALL BE HEARD
  # 4. (Missing)
  # 5. ActionView -- Rendered
  # 6. LoggingTestController -- Completed
  #
  let(:logging_test_controller) do
    stub_const(
      'LoggingTestController',
      Class.new(ActionController::Base) do
        def index
          logger.info 'MY VOICE SHALL BE HEARD!'

          render plain: 'OK'
        end
      end
    )
  end

  # defined in rails support apps
  let(:logs) { log_output.string }
  let(:log_entries) { logs.split("\n") }

  before do
    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configure do |c|
      c.tracing.instrument :rails
      c.tracing.log_injection = log_injection
    end

    allow(ENV).to receive(:[]).and_call_original
  end

  after do
    SemanticLogger.close

    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configuration.tracing[:semantic_logger].reset_options!
  end

  context 'with log injection enabled' do
    let(:log_injection) { true }

    context 'with Semantic Logger' do
      # for logsog_injection testing
      require 'rails_semantic_logger'

      subject(:response) { get '/logging' }

      context 'with semantic logger enabled' do
        context 'with semantic logger setup and no log_tags' do
          it 'injects trace_id into logs' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to_not be_empty

            if defined?(RailsSemanticLogger::ActionView::LogSubscriber) || Rails.version >= '5'
              expect(log_entries).to have(6).items

              expect(log_entries).to all include trace.id.to_s
              expect(log_entries).to all include 'ddsource: ruby'

              rack_started_entry,
                controller_processing_entry,
                controller_entry,
                _rendering_entry,
                _rendered_entry,
                controller_completed_entry = log_entries

              rack_span, controller_span, _render_span = spans

              expect(rack_started_entry).to include rack_span.id.to_s
              expect(controller_processing_entry).to include rack_span.id.to_s
              expect(controller_entry).to include controller_span.id.to_s

              # Flaky specs between tests due to ordering of active support subscriptions from
              # Datadog tracing and LogSubscriber. To debug, check the value for
              # `::ActiveSupport::Notifications.notifier.listeners_for("render_template.action_view")`
              #
              # The correct order should be
              # 1. RailsSemanticLogger::ActionView::LogSubscriber
              # 2. Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription
              #
              # expect(_rendering_entry).to include controller_span.id.to_s
              # expect(_rendered_entry).to include _render_span.id.to_s

              expect(controller_completed_entry).to include rack_span.id.to_s
            else
              expect(log_entries).to have(5).items

              expect(log_entries).to all include trace.id.to_s
              expect(log_entries).to all include 'ddsource: ruby'
            end
          end
        end

        context 'with semantic logger setup and existing log_tags' do
          let(:log_tags) { { some_tag: 'some_value' } }

          it 'injects trace correlation context into logs and preserve existing log tags' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to_not be_empty

            if defined?(RailsSemanticLogger::ActionView::LogSubscriber) || Rails.version >= '5'
              expect(log_entries).to have(6).items

              expect(log_entries).to all include(trace.id.to_s)
              expect(log_entries).to all include('ddsource: ruby')
              expect(log_entries).to all include('some_tag')
              expect(log_entries).to all include('some_value')

              rack_started_entry,
                controller_processing_entry,
                controller_entry,
                _rendering_entry,
                _rendered_entry,
                controller_completed_entry = log_entries

              rack_span, controller_span, _render_span = spans

              expect(rack_started_entry).to include rack_span.id.to_s
              expect(controller_processing_entry).to include rack_span.id.to_s
              expect(controller_entry).to include controller_span.id.to_s

              # Flaky specs between tests due to ordering of active support subscriptions from
              # Datadog tracing and LogSubscriber. To debug, check the value for
              # `::ActiveSupport::Notifications.notifier.listeners_for("render_template.action_view")`
              #
              # The correct order should be
              # 1. RailsSemanticLogger::ActionView::LogSubscriber
              # 2. Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription
              #
              # expect(_rendering_entry).to include controller_span.id.to_s
              # expect(_rendered_entry).to include _render_span.id.to_s

              expect(controller_completed_entry).to include rack_span.id.to_s
            else
              expect(log_entries).to have(5).items

              expect(log_entries).to all include(trace.id.to_s)
              expect(log_entries).to all include('ddsource: ruby')
              expect(log_entries).to all include('some_tag')
              expect(log_entries).to all include('some_value')
            end
          end
        end
      end
    end
  end

  context 'with log injection disabled' do
    let(:log_injection) { false }

    before do
      Datadog.configuration.tracing[:semantic_logger].enabled = false
    end

    context 'with Semantic Logger' do
      # for log_injection testing
      require 'rails_semantic_logger'

      subject(:response) { get '/logging' }

      context 'with semantic logger enabled' do
        context 'with semantic logger setup and no log_tags' do
          it 'does not inject trace_id into logs' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to_not be_empty

            if defined?(RailsSemanticLogger::ActionView::LogSubscriber) || Rails.version >= '5'
              expect(log_entries).to have(6).items
            else
              expect(log_entries).to have(5).items
            end

            log_entries.each do |l|
              expect(l).to_not be_empty

              expect(l).to_not include(trace.id.to_s)
              expect(l).to_not include('ddsource: ruby')
            end
          end
        end

        context 'with semantic logger setup and existing log_tags' do
          let(:log_tags) { { some_tag: 'some_value' } }

          it 'does not inject trace correlation context and preserve existing log tags' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to_not be_empty

            if defined?(RailsSemanticLogger::ActionView::LogSubscriber) || Rails.version >= '5'
              expect(log_entries).to have(6).items
            else
              expect(log_entries).to have(5).items
            end

            log_entries.each do |l|
              expect(l).to_not be_empty

              expect(l).to_not include(trace.id.to_s)
              expect(l).to_not include('ddsource: ruby')
              expect(l).to include('some_tag')
              expect(l).to include('some_value')
            end
          end
        end
      end
    end
  end
end
