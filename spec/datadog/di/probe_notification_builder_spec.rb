require "datadog/di/spec_helper"
require "datadog/di/probe_notification_builder"
require "datadog/di/serializer"
require "datadog/di/probe"
require "datadog/di/capture_expression"
require "datadog/di/el"

# Notification builder is primarily tested via integration tests for
# dynamic instrumentation overall, since the generated payloads depend
# heavily on probe attributes and parameters.
#
# The unit tests here are only meant to catch grave errors in the implementaton,
# not comprehensively verify correctness.

RSpec.describe Datadog::DI::ProbeNotificationBuilder do
  di_test

  let(:settings) do
    double("settings").tap do |settings|
      allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
      allow(settings).to receive(:service).and_return("test service")
      allow(settings).to receive(:env).and_return("test env")
      allow(settings).to receive(:version).and_return("test version")
      allow(settings).to receive(:tags).and_return({})
      allow(settings).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
    end
  end

  let(:di_settings) do
    double("di settings").tap do |settings|
      allow(settings).to receive(:enabled).and_return(true)
      allow(settings).to receive(:redacted_identifiers).and_return([])
      allow(settings).to receive(:redaction_excluded_identifiers).and_return([])
      allow(settings).to receive(:redacted_type_names).and_return(%w[])
      allow(settings).to receive(:max_capture_collection_size).and_return(10)
      allow(settings).to receive(:max_capture_attribute_count).and_return(10)
      allow(settings).to receive(:max_capture_depth).and_return(2)
      allow(settings).to receive(:max_capture_string_length).and_return(100)
      allow(settings).to receive(:max_time_to_serialize_ms).and_return(200)
    end
  end

  let(:redactor) { Datadog::DI::Redactor.new(settings) }
  let(:serializer) { Datadog::DI::Serializer.new(settings, redactor) }

  let(:logger) { instance_double(Datadog::Core::Logger).as_null_object }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }

  let(:builder) { described_class.new(settings, serializer, logger, telemetry: telemetry) }

  let(:probe) do
    Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1)
  end

  describe "#build_received" do
    let(:payload) do
      builder.build_received(probe)
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "RECEIVED",
          },
        },
        message: "Probe 123 has been received correctly",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with expected contents" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_installed" do
    let(:payload) do
      builder.build_installed(probe)
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "INSTALLED",
          },
        },
        message: "Probe 123 has been instrumented correctly",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with expected contents" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_emitting" do
    let(:payload) do
      builder.build_emitting(probe)
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "EMITTING",
          },
        },
        message: "Probe 123 is emitting",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with expected contents" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_errored" do
    let(:payload) do
      builder.build_errored(probe, Exception.new("Test message"))
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "ERROR",
            exception: {
              type: "Exception",
              message: "Test message",
            },
          },
        },
        message: "Instrumentation for probe 123 failed: Test message",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with expected contents" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_disabled" do
    let(:payload) do
      builder.build_disabled(probe, 0.75)
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "ERROR",
            exception: {
              type: "Error",
              message: "Probe 123 was disabled because it consumed 0.75 seconds of CPU time in DI processing",
            },
          },
        },
        message: "Probe 123 was disabled because it consumed 0.75 seconds of CPU time in DI processing",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with expected contents" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_status with ERROR status and no exception" do
    let(:payload) do
      builder.send(:build_status, probe,
        message: "Custom error message",
        status: "ERROR",
        exception: nil)
    end

    let(:expected) do
      {
        ddsource: "dd_debugger",
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: "123",
            probeVersion: 0,
            runtimeId: String,
            status: "ERROR",
            exception: {
              type: "Error",
              message: "Custom error message",
            },
          },
        },
        message: "Custom error message",
        service: "test service",
        timestamp: Integer,
      }
    end

    it "returns a hash with exception field using fallback values" do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe "#build_executed" do
    let(:payload) { builder.build_executed(context) }

    let(:context) do
      Datadog::DI::Context.new(
        settings: settings, serializer: serializer,
        probe: probe
      )
    end

    context "with template" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1,
          template_segments: ["hello world"])
      end

      let(:expected) do
        {
          ddsource: "dd_debugger",
          "dd.span_id": nil,
          "dd.trace_id": nil,
          debugger: {
            type: "snapshot",
            snapshot: {
              captures: {},
              evaluationErrors: [],
              id: String,
              language: "ruby",
              probe: {
                id: "123",
                location: {
                  file: nil,
                  lines: ["1"],
                },
                version: 0,
              },
              stack: nil,
              timestamp: Integer,
            },
          },
          message: "hello world",
          service: "test service",
          timestamp: Integer,
          logger: {
            method: nil,
            name: "X",
            thread_id: nil,
            thread_name: "Thread.main",
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      it "returns a hash with expected contents" do
        expect(payload).to be_a(Hash)
        expect(payload).to match(expected)
      end
    end

    context "without snapshot capture" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1,
          capture_snapshot: false)
      end

      let(:expected) do
        {
          ddsource: "dd_debugger",
          "dd.span_id": nil,
          "dd.trace_id": nil,
          debugger: {
            type: "snapshot",
            snapshot: {
              captures: {},
              evaluationErrors: [],
              id: String,
              language: "ruby",
              probe: {
                id: "123",
                location: {
                  file: nil,
                  lines: ["1"],
                },
                version: 0,
              },
              stack: nil,
              timestamp: Integer,
            },
          },
          message: nil,
          service: "test service",
          timestamp: Integer,
          logger: {
            method: nil,
            name: "X",
            thread_id: nil,
            thread_name: "Thread.main",
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      it "returns a hash with expected contents" do
        expect(payload).to be_a(Hash)
        expect(payload).to match(expected)
      end
    end

    context "with snapshot capture" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1,
          capture_snapshot: true,)
      end

      let(:context) do
        Datadog::DI::Context.new(probe: probe,
          settings: settings, serializer: serializer,
          path: "/foo.rb",
          locals: locals, target_self: Object.new)
      end

      let(:locals) do
        {foo: 1234}
      end

      let(:serialized_locals) do
        {foo: {type: "Integer", value: "1234"}}.freeze
      end

      let(:expected) do
        {
          ddsource: "dd_debugger",
          "dd.span_id": nil,
          "dd.trace_id": nil,
          debugger: {
            type: "snapshot",
            snapshot: {
              captures: {
                lines: {
                  1 => {
                    locals: serialized_locals,
                    arguments: {self: {
                      type: "Object",
                      fields: {},
                    }},
                  },
                },
              },
              evaluationErrors: [],
              id: String,
              language: "ruby",
              probe: {
                id: "123",
                location: {
                  file: "/foo.rb",
                  lines: ["1"],
                },
                version: 0,
              },
              stack: nil,
              timestamp: Integer,
            },
          },
          message: nil,
          service: "test service",
          timestamp: Integer,
          logger: {
            method: nil,
            name: "X",
            thread_id: nil,
            thread_name: "Thread.main",
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      it "returns a hash with expected contents" do
        expect(payload).to be_a(Hash)
        expect(payload).to match(expected)
      end
    end
  end

  describe "#build_executed with a BasicObject return value" do
    let(:probe) do
      Datadog::DI::Probe.new(id: "123", type: :log,
        type_name: "TestClass", method_name: "test_method",
        capture_snapshot: true,)
    end

    let(:context) do
      Datadog::DI::Context.new(
        probe: probe,
        settings: settings, serializer: serializer,
        target_self: Object.new,
        serialized_entry_args: {},
        return_value: ::BasicObject.new, duration: 0.1,
      )
    end

    # Snapshot serialization calls #class on the value being serialized, which
    # a BasicObject does not provide, so a BasicObject return value cannot be
    # serialized into the snapshot and the underlying NoMethodError surfaces.
    it "cannot serialize a BasicObject return value" do
      expect do
        builder.build_executed(context)
      end.to raise_error(NoMethodError, /undefined method .class./)
    end
  end

  describe "#build_executed for method probe with exception" do
    let(:probe) do
      Datadog::DI::Probe.new(id: "123", type: :log,
        type_name: "TestClass", method_name: "test_method",
        capture_snapshot: true,)
    end

    let(:target_self) { Object.new }

    context "when exception is present" do
      let(:exception) do
        raise NameError, "test error"
      rescue => e
        e
      end

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil, duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "populates throwable in captures" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:type]).to eq("NameError")
        expect(throwable[:message]).to eq("test error")
        expect(throwable[:stacktrace]).to be_an(Array)
        expect(throwable[:stacktrace]).not_to be_empty
        frame = throwable[:stacktrace].first
        expect(frame).to include(:fileName, :function, :lineNumber)
        expect(frame[:lineNumber]).to be_a(Integer)
        expect(frame[:fileName]).to eq(__FILE__)
      end
    end

    context "when exception is not present" do
      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: 42, duration: 0.1,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "has nil throwable in captures" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable).to be_nil
      end
    end

    context "when exception has overridden message method" do
      let(:exception_class) do
        Class.new(StandardError) do
          define_method(:message) do
            "overridden message"
          end
        end
      end

      let(:exception) { exception_class.new("constructor message") }

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil, duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "uses raw constructor message, not overridden message method" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:message]).to eq("constructor message")
        expect(throwable[:stacktrace]).to eq([])
        # Verify the override exists
        expect(exception.message).to eq("overridden message")
      end
    end

    context "when exception has nil constructor argument" do
      let(:exception) { StandardError.new(nil) }

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil, duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "reports nil message instead of NilClass" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:message]).to be_nil
        expect(throwable[:type]).to eq("StandardError")
        expect(throwable[:stacktrace]).to eq([])
      end
    end

    context "when exception has no constructor argument" do
      let(:exception) { StandardError.new }

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil, duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "reports nil message for no-argument exception" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:message]).to be_nil
        expect(throwable[:type]).to eq("StandardError")
        expect(throwable[:stacktrace]).to eq([])
      end
    end

    context "when exception has overridden backtrace method" do
      let(:exception_class) do
        Class.new(StandardError) do
          define_method(:backtrace) do
            ["overridden:0:in `fake_method'"]
          end
        end
      end

      let(:exception) do
        raise exception_class, "test"
      rescue => e
        e
      end

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings,
          serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil,
          duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "uses raw backtrace, not overridden backtrace method" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:stacktrace]).to be_an(Array)
        expect(throwable[:stacktrace]).to eq([])
        expect(throwable[:stacktrace]).not_to eq(
          [{fileName: "overridden", function: "fake_method", lineNumber: 0}],
        )
        # Verify the override exists on the Ruby side
        expect(exception.backtrace).to eq(["overridden:0:in `fake_method'"])
      end
    end

    context "when backtrace was set via set_backtrace with strings" do
      let(:exception) do
        e = StandardError.new("wrapped")
        e.set_backtrace(["/app/foo.rb:10:in `bar'", "/app/baz.rb:20:in `qux'"])
        e
      end

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings,
          serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil,
          duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "falls back to string backtrace parsing" do
        # set_backtrace with Array<String> causes backtrace_locations to
        # return nil. serialize_throwable should fall back to parsing the
        # string backtrace.
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:stacktrace]).to eq([
          {fileName: "/app/foo.rb", function: "bar", lineNumber: 10},
          {fileName: "/app/baz.rb", function: "qux", lineNumber: 20},
        ])
      end
    end

    context "when exception constructor argument is not a string" do
      let(:exception) { NameError.new(42) }

      let(:context) do
        Datadog::DI::Context.new(
          probe: probe,
          settings: settings, serializer: serializer,
          target_self: target_self,
          serialized_entry_args: {},
          return_value: nil, duration: 0.1,
          exception: exception,
        )
      end

      let(:payload) { builder.build_executed(context) }

      it "reports redacted placeholder for non-string constructor argument" do
        throwable = payload.dig(:debugger, :snapshot, :captures, :return, :throwable)
        expect(throwable[:message]).to eq("<REDACTED: not a string value>")
        expect(throwable[:type]).to eq("NameError")
        expect(throwable[:stacktrace]).to eq([])
      end
    end
  end

  describe "#evaluate_template" do
    context "when there are variables to be substituted" do
      let(:compiler) { Datadog::DI::EL::Compiler.new }

      let(:template_segments) do
        [
          Datadog::DI::EL::Expression.new("(expression)", *compiler.compile("ref" => "hello")),
          " ",
          Datadog::DI::EL::Expression.new("(expression)", *compiler.compile("ref" => "world")),
        ]
      end

      let(:vars) do
        {
          hello: "test",
          # We need double backslash to check for proper sub/gsub usage.
          world: %("'\\\\a\#{value}),
        }
      end

      let(:context) do
        Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          locals: vars,
          probe: probe
        )
      end

      let(:expected) { %(test "'\\\\a\#{value}) }

      it "substitutes correctly" do
        expect(builder.send(:evaluate_template, template_segments, context)).to eq([expected, []])
      end
    end
  end

  describe "#build_snapshot with capture_expressions" do
    let(:compiled_expr) do
      Datadog::DI::EL::Expression.new("x", *Datadog::DI::EL::Compiler.new.compile({"ref" => "x"}))
    end

    let(:capture_expression) do
      Datadog::DI::CaptureExpression.new(name: "x", expr: compiled_expr)
    end

    let(:context) do
      Datadog::DI::Context.new(
        settings: settings, serializer: serializer,
        probe: probe,
        locals: {x: 42},
        target_self: nil,
      )
    end

    context "line probe with only capture_expressions" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1,
          capture_expressions: [capture_expression])
      end

      it "emits captureExpressions under the line block" do
        payload = builder.build_snapshot(context)
        lines = payload[:debugger][:snapshot][:captures][:lines]
        expect(lines.keys).to eq([1])
        expect(lines[1][:captureExpressions].keys).to eq(["x"])
        expect(lines[1][:captureExpressions]["x"]).to include(type: "Integer", value: "42")
      end

      it "does not emit locals or arguments blocks alongside captureExpressions" do
        payload = builder.build_snapshot(context)
        lines = payload[:debugger][:snapshot][:captures][:lines]
        expect(lines[1]).not_to have_key(:locals)
        expect(lines[1]).not_to have_key(:arguments)
      end
    end

    context "method probe with only capture_expressions" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, type_name: "Foo", method_name: "bar",
          capture_expressions: [capture_expression])
      end

      it "emits captureExpressions in the return block and omits the entry block" do
        payload = builder.build_snapshot(context)
        captures = payload[:debugger][:snapshot][:captures]
        expect(captures).not_to have_key(:entry)
        expect(captures[:return][:captureExpressions].keys).to eq(["x"])
        expect(captures[:return][:captureExpressions]["x"]).to include(type: "Integer", value: "42")
      end
    end

    context "method probe with capture_expressions and an exception in context" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, type_name: "Foo", method_name: "bar",
          capture_expressions: [capture_expression])
      end

      let(:raised_exception) do
        raise "boom"
      rescue => e
        e
      end

      let(:context) do
        Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          probe: probe,
          locals: {x: 42},
          target_self: Object.new,
          exception: raised_exception,
        )
      end

      it "emits throwable in the return block alongside captureExpressions" do
        payload = builder.build_snapshot(context)
        return_block = payload[:debugger][:snapshot][:captures][:return]
        expect(return_block[:captureExpressions].keys).to eq(["x"])
        expect(return_block[:throwable][:type]).to eq("RuntimeError")
      end
    end

    context "captureSnapshot wins when both are set" do
      let(:target_self) { Object.new }

      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, type_name: "Foo", method_name: "bar",
          capture_snapshot: true,
          capture_expressions: [capture_expression])
      end

      let(:context) do
        Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          probe: probe,
          target_self: target_self,
          return_value: 99,
        )
      end

      it "emits the snapshot blocks and omits captureExpressions" do
        payload = builder.build_snapshot(context)
        captures = payload[:debugger][:snapshot][:captures]
        expect(captures[:return][:arguments]).to be_a(Hash)
        expect(captures[:entry]).not_to have_key(:captureExpressions)
        expect(captures[:return]).not_to have_key(:captureExpressions)
      end
    end

    context "method probe with evaluate_at: :entry" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, type_name: "Foo", method_name: "bar",
          evaluate_at: :entry,
          capture_expressions: [capture_expression])
      end

      let(:context) do
        Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          probe: probe,
          target_self: nil,
          entry_capture_expressions: {"x" => {type: "Integer", value: "7"}},
          entry_capture_evaluation_errors: [],
          return_value: 999,
        )
      end

      it "emits captureExpressions under the entry block and omits the return block" do
        payload = builder.build_snapshot(context)
        captures = payload[:debugger][:snapshot][:captures]
        expect(captures).to have_key(:entry)
        expect(captures).not_to have_key(:return)
        expect(captures[:entry][:captureExpressions]).to eq({"x" => {type: "Integer", value: "7"}})
      end

      it "consumes pre-computed entry-time block; does not re-evaluate against exit scope" do
        payload = builder.build_snapshot(context)
        expect(payload[:debugger][:snapshot][:captures][:entry][:captureExpressions]["x"][:value]).to eq("7")
      end

      it "merges entry-time evaluation errors into the snapshot evaluationErrors array" do
        context = Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          probe: probe, target_self: nil,
          entry_capture_expressions: {},
          entry_capture_evaluation_errors: [{expr: "x", message: "NameError: badvar"}],
        )
        payload = builder.build_snapshot(context)
        errors = payload[:debugger][:snapshot][:evaluationErrors]
        expect(errors).to include(expr: "x", message: "NameError: badvar")
      end

      it "emits an empty captureExpressions hash when no entry block was stashed" do
        context = Datadog::DI::Context.new(
          settings: settings, serializer: serializer,
          probe: probe, target_self: nil,
        )
        payload = builder.build_snapshot(context)
        captures = payload[:debugger][:snapshot][:captures]
        expect(captures[:entry][:captureExpressions]).to eq({})
        expect(captures).not_to have_key(:return)
      end
    end

    context "evaluation error in a capture expression" do
      let(:failing_expr) do
        Datadog::DI::EL::Expression.new("len(badvar)", *Datadog::DI::EL::Compiler.new.compile({"len" => {"ref" => "badvar"}}))
      end

      let(:probe) do
        Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1,
          capture_expressions: [Datadog::DI::CaptureExpression.new(name: "bad", expr: failing_expr)])
      end

      it "omits the failing key from captureExpressions and reports in top-level evaluationErrors" do
        payload = builder.build_snapshot(context)
        snapshot = payload[:debugger][:snapshot]
        expect(snapshot[:captures][:lines][1][:captureExpressions]).to eq({})
        expect(snapshot[:evaluationErrors].size).to eq(1)
        expect(snapshot[:evaluationErrors].first[:expr]).to eq("bad")
        expect(snapshot[:evaluationErrors].first[:message]).to include("ExpressionEvaluationError")
      end
    end
  end

  describe "process tags" do
    let(:probe) do
      Datadog::DI::Probe.new(id: "123", type: :log, file: "X", line_no: 1)
    end

    let(:context) do
      Datadog::DI::Context.new(
        settings: settings, serializer: serializer,
        probe: probe
      )
    end

    context "when process tags propagation is enabled" do
      before do
        allow(settings).to receive(:experimental_propagate_process_tags_enabled).and_return(true)
      end

      it "includes process tags in the payload" do
        payload = builder.build_executed(context)
        expect(payload[:process_tags]).to eq(Datadog::Core::Environment::Process.serialized)
        expect(payload[:process_tags]).to include("entrypoint.workdir")
        expect(payload[:process_tags]).to include("entrypoint.name")
        expect(payload[:process_tags]).to include("entrypoint.basedir")
        expect(payload[:process_tags]).to include("entrypoint.type")
      end
    end

    context "when process tags propagation is not enabled" do
      before do
        allow(settings).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
      end

      it "excludes process tags in the payload" do
        payload = builder.build_executed(context)
        expect(payload).not_to include(:process_tags)
      end
    end
  end
end
