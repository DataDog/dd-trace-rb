# frozen_string_literal: true

require "datadog/core"

RSpec.describe "Datadog::Tracing::Transport::Native::TraceExporter" do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:trace_exporter_class) { native_module::TraceExporter }

  describe "._native_new" do
    context "with all string arguments" do
      it "creates an exporter" do
        exporter = trace_exporter_class._native_new(
          url: "http://127.0.0.1:8126",
          tracer_version: "1.0.0",
          language: "ruby",
          language_version: RUBY_VERSION,
          language_interpreter: RUBY_ENGINE,
          hostname: "testhost",
          env: "test",
          service: "testsvc",
          version: "1.0",
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context "with nil for all optional arguments" do
      it "creates an exporter" do
        exporter = trace_exporter_class._native_new(
          url: "http://127.0.0.1:8126",
          tracer_version: nil, language: nil, language_version: nil,
          language_interpreter: nil, hostname: nil, env: nil,
          service: nil, version: nil,
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context "with a non-string url" do
      it "raises TypeError" do
        expect {
          trace_exporter_class._native_new(
            url: 12345,
            tracer_version: nil, language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        }.to raise_error(TypeError)
      end
    end

    context "with a non-string optional argument" do
      it "raises TypeError" do
        expect {
          trace_exporter_class._native_new(
            url: "http://127.0.0.1:8126",
            tracer_version: 123, # should be String or nil
            language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        }.to raise_error(TypeError)
      end
    end

    context "with invalid UTF-8 configuration" do
      it "rejects the config before creating a shared runtime" do
        invalid = "\xFF".b.force_encoding(Encoding::UTF_8)

        20.times do
          expect {
            trace_exporter_class._native_new(
              url: "http://127.0.0.1:8126",
              tracer_version: nil, language: nil, language_version: nil,
              language_interpreter: nil, hostname: nil, env: nil,
              service: nil, version: invalid,
            )
          }.to raise_error(RuntimeError, /version/)
        end
      end
    end

    it "cannot be allocated directly" do
      expect { trace_exporter_class.new }.to raise_error(TypeError)
    end

    it "cleans up invalid telemetry identity during construction", :native_transport_memcheck do
      skip "Requires fork-safe telemetry APIs" unless trace_exporter_class._native_telemetry_supported?

      5.times do
        expect {
          trace_exporter_class._native_new(
            url: "http://127.0.0.1:8126",
            tracer_version: "1.0.0", language: "ruby", language_version: RUBY_VERSION,
            language_interpreter: RUBY_ENGINE, hostname: nil, env: nil,
            service: "test", version: nil,
            runtime_id: "\xff".b, telemetry_interval: 1000,
          )
        }.to raise_error(ArgumentError, /identity/)
      end
      GC.start
    end

    it "reclaims telemetry workers on explicit close and GC", :native_transport_memcheck do
      skip "Requires fork-safe telemetry APIs" unless trace_exporter_class._native_telemetry_supported?

      6.times do |index|
        exporter = trace_exporter_class._native_new(
          url: "http://127.0.0.1:9",
          tracer_version: "1.0.0", language: "ruby", language_version: RUBY_VERSION,
          language_interpreter: RUBY_ENGINE, hostname: nil, env: nil,
          service: "test", version: nil,
          runtime_id: "5fa789ed-91b6-4b9d-a7c9-17e0e461d09b", telemetry_interval: 3600000,
          shutdown_timeout: 10000,
        )
        exporter._native_close if index.even?
      end
      GC.start
    end

    it "rejects a non-boolean client-computed stats setting" do
      expect {
        trace_exporter_class._native_new(
          url: "http://127.0.0.1:8126",
          tracer_version: nil, language: nil, language_version: nil,
          language_interpreter: nil, hostname: nil, env: nil,
          service: nil, version: nil, client_computed_stats: "true",
        )
      }.to raise_error(TypeError, /client_computed_stats/)
    end

    context "GC safety" do
      {"1000" => TypeError, -1 => RangeError, 2**63 => RangeError}.each do |timeout, error|
        it "rejects timeout #{timeout.inspect} before allocating an exporter", :native_transport_memcheck do
          expect {
            trace_exporter_class._native_new(
              url: "http://127.0.0.1:9",
              tracer_version: nil, language: nil, language_version: nil,
              language_interpreter: nil, hostname: nil, env: nil,
              service: nil, version: nil, timeout_milliseconds: timeout,
            )
          }.to raise_error(error)
        end
      end

      it "closes native resources once and tolerates captured fork hooks", :native_transport_memcheck do
        exporter = trace_exporter_class._native_new(
          url: "http://127.0.0.1:9",
          tracer_version: nil, language: nil, language_version: nil,
          language_interpreter: nil, hostname: nil, env: nil,
          service: nil, version: nil,
        )

        exporter._native_close
        expect { exporter._native_close }.not_to raise_error
        expect { exporter._native_before_fork }.not_to raise_error
        expect { exporter._native_after_fork_in_parent }.not_to raise_error
        expect { exporter._native_after_fork_in_child }.not_to raise_error
      end

      it "releases resources when close is interrupted", :native_transport_memcheck do
        exporter = trace_exporter_class._native_new(
          url: "http://127.0.0.1:9",
          tracer_version: nil, language: nil, language_version: nil,
          language_interpreter: nil, hostname: nil, env: nil,
          service: nil, version: nil,
        )

        expect {
          Thread.handle_interrupt(Interrupt => :never) do
            Thread.current.raise(Interrupt, "interrupted close")
            Thread.handle_interrupt(Interrupt => :on_blocking) { exporter._native_close }
          end
        }.to raise_error(Interrupt, "interrupted close")
        expect { exporter._native_send_traces([], false) }.to raise_error(RuntimeError, /already freed/)
        expect { exporter._native_close }.not_to raise_error
      ensure
        exporter&._native_close
      end

      it "does not crash when instances are garbage collected" do
        5.times do
          trace_exporter_class._native_new(
            url: "http://127.0.0.1:8126",
            tracer_version: nil, language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        end
        GC.start
        GC.start
      end
    end
  end
end
