require 'datadog/tracing'
require 'datadog/opentracer'
require 'datadog/statsd'

RSpec.describe 'Datadog integration' do
  context 'graceful shutdown', :integration do
    before do
      # TODO: This test is flaky, and the flakiness affects JRuby really often.
      # Until we can investigate it, let's skip it as the constant failures impact unrelated development.
      if PlatformHelpers.jruby?
        skip('TODO: This test is flaky, and triggers very often on JRuby. Requires further investigation.')
      end
    end

    subject(:shutdown) { Datadog.shutdown! }

    let(:start_tracer) do
      Datadog::Tracing.trace('test.op') {}
    end

    def wait_for_tracer_sent
      try_wait_until { Datadog::Tracing.send(:tracer).writer.transport.stats.success > 0 }
    end

    context 'for threads' do
      let(:original_threads) { Thread.list }
      let!(:original_threads_inspect) { inspect_threads(original_threads) } # Store result as stack trace will change
      let(:threads) { Thread.list }

      def inspect_threads(threads)
        threads.map.with_index { |t, idx| "#{idx}=#{t.backtrace}" }.join(';')
      end

      it 'closes tracer threads' do
        start_tracer
        wait_for_tracer_sent

        shutdown

        expect(threads.size).to eq(original_threads.size),
          "Expected #{original_threads.size} threads (#{original_threads_inspect}), "\
                  "got #{threads.size} threads (#{inspect_threads(threads)})"
      end
    end

    context 'for file descriptors' do
      def open_file_descriptors
        # Unix-specific way to get the current process' open file descriptors and the files (if any) they correspond to
        Dir['/dev/fd/*'].each_with_object({}) do |fd, hash|
          hash[fd] =
            begin
              File.realpath(fd)
            rescue SystemCallError # This can fail due to... reasons, and we only want it for debugging so let's ignore
              nil
            end
        end
      end

      it 'closes tracer file descriptors (known flaky test)' do
        before_open_file_descriptors = open_file_descriptors

        start_tracer
        wait_for_tracer_sent

        shutdown

        after_open_file_descriptors = open_file_descriptors

        expect(after_open_file_descriptors.size)
          .to(
            # Below was changed from eq to <= to cause less flakyness. We still don't know why this test fails in CI
            # from time to time.
            (be <= (before_open_file_descriptors.size)),
            lambda {
              "Open fds before (#{before_open_file_descriptors.size}): #{before_open_file_descriptors}\n" \
              "Open fds after (#{after_open_file_descriptors.size}):  #{after_open_file_descriptors}"
            }
          )
      end
    end
  end

  context 'after shutdown' do
    subject(:shutdown!) { Datadog.shutdown! }

    before do
      Datadog.configure do |c|
        c.diagnostics.health_metrics.enabled = true
      end

      shutdown!
    end

    after do
      Datadog.configuration.diagnostics.health_metrics.reset!
      Datadog.shutdown!
    end

    context 'calling public apis' do
      it 'does not error on tracing' do
        span_op = Datadog::Tracing.trace('test')

        expect(span_op.finish).to be_truthy
      end

      it 'does not error on tracing with block' do
        value = Datadog::Tracing.trace('test') do |span_op|
          expect(span_op).to be_a(Datadog::Tracing::SpanOperation)
          :return
        end

        expect(value).to be(:return)
      end

      it 'does not error on logging' do
        expect(Datadog.logger.info('test')).to be true
      end

      it 'does not error on configuration access' do
        expect(Datadog.configuration.runtime_metrics.enabled).to be(true).or be(false)
      end

      it 'does not error on reporting health metrics' do
        expect { Datadog.health_metrics.queue_accepted(1) }.to_not raise_error
      end

      context 'with OpenTracer' do
        before do
          OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
        end

        let(:tracer) do
          OpenTracing.global_tracer
        end

        it 'does not error on tracing' do
          span = tracer.start_span('test')

          expect { span.finish }.to_not raise_error
        end

        it 'does not error on tracing with block' do
          scope = tracer.start_span('test') do |scp|
            expect(scp).to be_a(OpenTracing::Scope)
          end

          expect(scope).to be_a(OpenTracing::Span)
        end

        it 'does not error on registered scope tracing' do
          span = tracer.start_active_span('test')

          expect { span.close }.to_not raise_error
        end

        it 'does not error on registered scope tracing with block' do
          scope = tracer.start_active_span('test') do |scp|
            expect(scp).to be_a(OpenTracing::Scope)
          end

          expect(scope).to be_a(OpenTracing::Scope)
        end
      end
    end
  end
end
