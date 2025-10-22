require 'datadog/tracing/contrib/support/spec_helper'

require 'action_controller'
require 'datadog'

# TODO: We plan on rewriting much of this instrumentation to bring it up to
#       present day patterns/conventions. For now, just test a few known cases.
RSpec.describe Datadog::Tracing::Contrib::ActionPack::ActionController::Instrumentation do
  describe '::finish_processing' do
    subject(:finish_processing) { described_class.finish_processing(payload) }

    context 'given a payload that been started' do
      before { described_class.start_processing(payload) }
      after { span.finish }

      let(:action_dispatch_exception) { nil }
      let(:action_name) { 'index' }
      let(:controller_class) { stub_const('TestController', Class.new(ActionController::Base)) }
      let(:env) { {'rack.url_scheme' => 'http'} }
      let(:payload) do
        {
          controller: controller_class,
          action: action_name,
          env: env,
          headers: {
            # The exception this controller was given in the request,
            # which is typical if the controller is configured to handle exceptions.
            request_exception: action_dispatch_exception
          },
          tracing_context: {},
        }
      end

      let(:span) { payload[:tracing_context][:dd_request_span] }

      context 'with a 200 OK response' do
        before do
          expect(Datadog.logger).to_not receive(:error)
          finish_processing
        end

        describe 'the Datadog span' do
          it do
            expect(span).to_not have_error
          end
        end
      end

      context 'with a status code set in the payload' do
        let(:payload) do
          super().merge(status: 404)
        end

        describe 'the Datadog span' do
          before do
            expect(Datadog.logger).to_not receive(:error)
            finish_processing
          end

          it do
            expect(span).to_not have_error
          end
        end

        context 'when http_error_statuses.server is set to match the status code' do
          before do
            Datadog.configure do |c|
              c.tracing.http_error_statuses.server = 400..599
            end
          end

          describe 'the Datadog span' do
            before do
              expect(Datadog.logger).to_not receive(:error)
              finish_processing
            end

            it do
              expect(span).to have_error
            end
          end
        end
      end

      context 'with a 500 Server Error response' do
        let(:error) do
          raise 'Test error'
        rescue => e
          e
        end

        let(:payload) do
          super().merge(
            exception: [error.class.name, error.message],
            exception_object: error
          )
        end

        before do
          expect(Datadog.logger).to_not receive(:error)
          finish_processing
        end

        describe 'the Datadog span' do
          it do
            expect(span).to have_error
          end
        end
      end

      context 'with a 404 Not Found response' do
        let(:error) { ::ActionController::RoutingError.new('Not Found') }
        let(:payload) do
          super().merge(
            exception: [error.class.name, error.message],
            exception_object: error
          )
        end

        describe 'the Datadog span' do
          before do
            expect(Datadog.logger).to_not receive(:error)
            finish_processing
          end

          it do
            expect(span).to_not have_error
          end
        end

        context 'when http_error_statuses.server is set to match 404' do
          before do
            Datadog.configure do |c|
              c.tracing.http_error_statuses.server = 400..599
            end
          end

          describe 'the Datadog span' do
            before do
              expect(Datadog.logger).to_not receive(:error)
              finish_processing
            end

            it do
              expect(span).to have_error
            end
          end
        end
      end
    end
  end
end
