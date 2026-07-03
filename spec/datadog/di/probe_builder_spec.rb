require "datadog/di/spec_helper"
require "datadog/di/probe_builder"
require "datadog/di/logger"

RSpec.describe Datadog::DI::ProbeBuilder do
  di_test

  let(:logger) { instance_double(Datadog::DI::Logger).as_null_object }

  describe ".build_from_remote_config" do
    let(:probe) do
      described_class.build_from_remote_config(rc_probe_spec, logger: logger)
    end

    context "typical line probe" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [4321]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         # Use a value different from our library default to ensure that
         # it is correctly processed.
         "capture" => {"maxReferenceDepth" => 33, 'maxFieldCount' => 34},
         # Use a value different from our library default to ensure that
         # it is correctly processed.
         "sampling" => {"snapshotsPerSecond" => 4500},
         "evaluateAt" => "EXIT"}
      end

      it "creates line probe with corresponding values" do
        expect(probe.id).to eq "3ecfd456-2d7c-4359-a51f-d4cc44141ffe"
        expect(probe.type).to eq :log
        expect(probe.file).to eq "aaa.rb"
        expect(probe.line_no).to eq 4321
        expect(probe.type_name).to be nil
        expect(probe.method_name).to be nil
        expect(probe.max_capture_depth).to eq 33
        expect(probe.max_capture_attribute_count).to eq 34
        expect(probe.rate_limit).to eq 4500

        expect(probe.line?).to be true
        expect(probe.method?).to be false
      end
    end

    context "minimum set of fields" do
      # This is a made up payload to test attribute defaulting.
      # In practice payloads like this should not be seen.
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "type" => "LOG_PROBE",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [4321]},}
      end

      describe ".max_capture_depth" do
        it "is nil" do
          expect(probe.max_capture_depth).to be nil
        end
      end

      describe ".rate_limit" do
        it "is defaulted to 5000" do
          expect(probe.rate_limit).to eq 5000
        end
      end
    end

    context "when lines is an array of nil" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [nil]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      describe "construction" do
        it "fails with exception" do
          expect do
            probe
          end.to raise_error(ArgumentError, /neither method nor line probe/)
        end
      end
    end

    context "RC payload with capture snapshot" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa", "lines" => [2]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => true,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      it "capture_snapshot? is true" do
        expect(probe.capture_snapshot?).to be true
      end
    end

    context "RC payload without capture snapshot" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa", "lines" => [4]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      it "capture_snapshot? is false" do
        expect(probe.capture_snapshot?).to be false
      end
    end

    context 'when conditions are given' do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa", "lines" => [4]},
         "when" => {
           "dsl" => "contains(value, \"StringLiteral\")",
           "json" => {
             "contains" => [
               {
                 "ref" => "value"
               },
               "StringLiteral"
             ]
           }
         },
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => true,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      it "condition on probe is the compiled condition" do
        expect(probe.condition).to be_a(Datadog::DI::EL::Expression)
      end
    end

    context "empty input" do
      let(:rc_probe_spec) { {} }

      it "raises ArgumentError" do
        expect do
          probe
        end.to raise_error(ArgumentError, /Malformed remote configuration entry/)
      end
    end

    context "capture expressions" do
      let(:base_spec) do
        {
          "id" => "ce-test",
          "type" => "LOG_PROBE",
          "where" => {"typeName" => "Foo", "methodName" => "bar"},
          "template" => "",
          "segments" => [],
          "captureSnapshot" => false,
        }
      end

      let(:valid_capture_expression) do
        {
          "name" => "x",
          "expr" => {"dsl" => "x", "json" => {"ref" => "x"}},
        }
      end

      context "with a valid captureExpressions entry" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [valid_capture_expression])
        end

        it "creates a probe with capture expressions" do
          expect(probe.capture_expressions.size).to eq(1)
          expect(probe.capture_expressions.first.name).to eq("x")
          expect(probe.capture_expressions.first.expr).to be_a(Datadog::DI::EL::Expression)
          expect(probe.capture_expressions.first.limits).to be_nil
        end

        it "defaults to snapshot-class rate limit (1/sec)" do
          expect(probe.rate_limit).to eq(1)
        end
      end

      context "with per-expression capture limits" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [
            valid_capture_expression.merge("capture" => {
              "maxReferenceDepth" => 7,
              "maxCollectionSize" => 17,
              "maxLength" => 50,
              "maxFieldCount" => 11,
            }),
          ])
        end

        it "populates CaptureLimits with the per-expression values" do
          limits = probe.capture_expressions.first.limits
          expect(limits).to be_a(Datadog::DI::CaptureLimits)
          expect(limits.max_reference_depth).to eq(7)
          expect(limits.max_collection_size).to eq(17)
          expect(limits.max_length).to eq(50)
          expect(limits.max_field_count).to eq(11)
        end
      end

      context "name violates the backend pattern" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [
            valid_capture_expression.merge("name" => "invalid-name-with-hyphens"),
          ])
        end

        it "raises ArgumentError" do
          expect { probe }.to raise_error(ArgumentError, /name missing or invalid/)
        end
      end

      context "missing expr" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [{"name" => "x"}])
        end

        it "raises ArgumentError" do
          expect { probe }.to raise_error(ArgumentError, /missing or malformed expr/)
        end
      end

      context "empty captureExpressions array" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [])
        end

        it "creates a probe with no capture expressions" do
          expect(probe.capture_expressions).to eq([])
          expect(probe.capture_expressions?).to be false
        end
      end

      context "non-Array captureExpressions value" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => 5)
        end

        it "raises ArgumentError with the offending type" do
          expect { probe }.to raise_error(ArgumentError, /captureExpressions must be an array, got: Integer/)
        end
      end

      context "captureSnapshot=true and non-empty captureExpressions (mutual exclusion at fire time)" do
        let(:rc_probe_spec) do
          base_spec.merge(
            "captureSnapshot" => true,
            "captureExpressions" => [valid_capture_expression],
          )
        end

        it "creates the probe successfully (mutual exclusion resolved at fire time)" do
          expect(probe.capture_snapshot?).to be true
          expect(probe.capture_expressions?).to be true
        end

        it "logs a debug message about snapshot winning" do
          expect(logger).to receive(:debug) do |&block|
            expect(block.call).to match(/captureSnapshot=true wins over captureExpressions/)
          end
          probe
        end
      end

      context "duplicate captureExpressions names" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [
            {"name" => "x", "expr" => {"dsl" => "a", "json" => {"ref" => "a"}}},
            {"name" => "y", "expr" => {"dsl" => "b", "json" => {"ref" => "b"}}},
            {"name" => "x", "expr" => {"dsl" => "c", "json" => {"ref" => "c"}}},
          ])
        end

        it "collapses to one entry per name, keeping the last occurrence" do
          expect(probe.capture_expressions.map(&:name)).to eq(%w[x y])
          x = probe.capture_expressions.find { |ce| ce.name == "x" }
          expect(x.expr.dsl_expr).to eq("c")
        end

        it "logs a debug message about the collapse" do
          expect(logger).to receive(:debug) do |&block|
            expect(block.call).to match(/collapsed duplicate captureExpressions names/)
          end
          probe
        end
      end

      context "captureExpressions is not an array" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => {"name" => "x"})
        end

        it "raises ArgumentError" do
          expect { probe }.to raise_error(ArgumentError, /captureExpressions must be an array/)
        end
      end

      context "captureExpressions entry is not a hash" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => ["not-a-hash"])
        end

        it "raises ArgumentError" do
          expect { probe }.to raise_error(ArgumentError, /captureExpressions entry must be a hash/)
        end
      end

      context "per-expression capture block is not a hash" do
        let(:rc_probe_spec) do
          base_spec.merge("captureExpressions" => [
            valid_capture_expression.merge("capture" => "not-a-hash"),
          ])
        end

        it "raises ArgumentError" do
          expect { probe }.to raise_error(ArgumentError, /capture-expression entry capture must be a hash/)
        end
      end
    end

    describe "evaluateAt parsing" do
      let(:base_spec) do
        {"id" => "42", "type" => "LOG_PROBE",
         "where" => {"typeName" => "Foo", "methodName" => "bar"}}
      end

      context "absent" do
        let(:rc_probe_spec) { base_spec }

        it "defaults probe.evaluate_at to :exit" do
          expect(probe.evaluate_at).to eq(:exit)
        end
      end

      context "explicit nil" do
        let(:rc_probe_spec) { base_spec.merge("evaluateAt" => nil) }

        it "defaults probe.evaluate_at to :exit" do
          expect(probe.evaluate_at).to eq(:exit)
        end
      end

      context "\"ENTRY\"" do
        let(:rc_probe_spec) { base_spec.merge("evaluateAt" => "ENTRY") }

        it "maps to :entry" do
          expect(probe.evaluate_at).to eq(:entry)
        end
      end

      context "\"EXIT\"" do
        let(:rc_probe_spec) { base_spec.merge("evaluateAt" => "EXIT") }

        it "maps to :exit" do
          expect(probe.evaluate_at).to eq(:exit)
        end
      end

      context "\"DEFAULT\" (Java sends this)" do
        let(:rc_probe_spec) { base_spec.merge("evaluateAt" => "DEFAULT") }

        it "maps to :exit (matching libdatadog default)" do
          expect(probe.evaluate_at).to eq(:exit)
        end
      end

      context "unrecognized string" do
        let(:rc_probe_spec) { base_spec.merge("evaluateAt" => "AROUND") }

        it "falls back to :exit" do
          expect(probe.evaluate_at).to eq(:exit)
        end

        it "logs a debug message naming the bad value" do
          expect(logger).to receive(:debug) do |&block|
            expect(block.call).to match(/unrecognized evaluateAt value "AROUND"/)
          end
          probe
        end
      end
    end
  end
end
