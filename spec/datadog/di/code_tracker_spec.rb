require 'datadog/di'
require 'datadog/di/code_tracker'
require "datadog/di/spec_helper"

RSpec.describe Datadog::DI::CodeTracker do
  di_test
  deactivate_code_tracking

  let(:tracker) do
    described_class.new
  end

  shared_context 'when code tracker is running' do
    before do
      # Stub backfill so tests that use this context only exercise
      # :script_compiled behavior, not backfill.
      allow(tracker).to receive(:backfill_registry)
      tracker.start
    end

    after do
      tracker.stop
    end
  end

  describe "#start" do
    before do
      # Stub backfill so :script_compiled tests aren't affected by
      # backfill populating the registry with pre-loaded files.
      allow(tracker).to receive(:backfill_registry)
    end

    after do
      tracker.stop
    end

    it "tracks loaded file" do
      # The expectations appear to be lazy-loaded, therefore
      # we need to invoke the same expectation before starting
      # code tracking as we'll be using later in the test.
      expect(tracker.send(:registry)).to be_empty
      tracker.start
      # Should still be empty here.
      expect(tracker.send(:registry)).to be_empty
      load File.join(File.dirname(__FILE__), "code_tracker_load_class.rb")
      expect(tracker.send(:registry).length).to eq(1)

      path = tracker.send(:registry).to_a.dig(0, 0)
      # The path in the registry should be absolute.
      expect(path[0]).to eq "/"
      # The full path is dependent on the environment/system
      # running the tests, but we can assert on the basename
      # which will be the same.
      expect(File.basename(path)).to eq("code_tracker_load_class.rb")
      # And, we should in fact have a full path.
      expect(path).to start_with("/")
    end

    it "tracks required file" do
      # The expectations appear to be lazy-loaded, therefore
      # we need to invoke the same expectation before starting
      # code tracking as we'll be using later in the test.
      expect(tracker.send(:registry)).to be_empty
      tracker.start
      # Should still be empty here.
      expect(tracker.send(:registry)).to be_empty
      require_relative "code_tracker_require_class"
      expect(tracker.send(:registry).length).to eq(1)

      path = tracker.send(:registry).to_a.dig(0, 0)
      # The path in the registry should be absolute.
      expect(path[0]).to eq "/"
      # The full path is dependent on the environment/system
      # running the tests, but we can assert on the basename
      # which will be the same.
      expect(File.basename(path)).to eq("code_tracker_require_class.rb")
      # And, we should in fact have a full path.
      expect(path).to start_with("/")
    end

    context "eval without location" do
      it "does not track eval'd code" do
        # The expectations appear to be lazy-loaded, therefore
        # we need to invoke the same expectation before starting
        # code tracking as we'll be using later in the test.
        expect(tracker.send(:registry)).to be_empty
        tracker.start
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
        eval "1 + 2" # standard:disable Style/EvalWithLocation
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
      end
    end

    context "eval with location" do
      it "does not track eval'd code" do
        # The expectations appear to be lazy-loaded, therefore
        # we need to invoke the same expectation before starting
        # code tracking as we'll be using later in the test.
        expect(tracker.send(:registry)).to be_empty
        tracker.start
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
        eval "1 + 2", nil, __FILE__, __LINE__
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
      end
    end

    context 'when process forks' do
      it 'continues tracking in the fork' do
        # Load rspec assertion code
        expect(1).to eq(1)
        expect(1).to equal(1)

        expect(tracker.send(:registry)).to be_empty
        tracker.start

        require_relative 'code_tracker_test_class_4'
        expect(tracker.send(:registry).length).to eq(1)
        path = tracker.send(:registry).to_a.dig(0, 0)
        expect(File.basename(path)).to eq("code_tracker_test_class_4.rb")

        expect_in_fork do
          expect(tracker.send(:registry).length).to eq(1)
          path = tracker.send(:registry).to_a.dig(0, 0)
          expect(File.basename(path)).to eq("code_tracker_test_class_4.rb")

          require_relative 'code_tracker_test_class_5'
          expect(tracker.send(:registry).length).to eq(2)
          path = tracker.send(:registry).to_a.dig(1, 0)
          expect(File.basename(path)).to eq("code_tracker_test_class_5.rb")
        end

        begin
          Process.waitpid
        rescue Errno::ECHILD
        end

        # Verify parent did not change
        expect(tracker.send(:registry).length).to eq(1)
        path = tracker.send(:registry).to_a.dig(0, 0)
        expect(File.basename(path)).to eq("code_tracker_test_class_4.rb")
      end
    end
  end

  describe "#active?" do
    context "when started" do
      include_context 'when code tracker is running'

      it "is true" do
        expect(tracker.active?).to be true
      end
    end

    context "when stopped" do
      before do
        tracker.start
        tracker.stop
      end

      it "is false" do
        expect(tracker.active?).to be false
      end
    end
  end

  describe 'line probe installation' do
    let(:component) do
      instance_double(Datadog::DI::Component).tap do |component|
        expect(component).to receive(:probe_manager).and_return(probe_manager)
      end
    end

    let(:probe_manager) do
      instance_double(Datadog::DI::ProbeManager)
    end

    context 'when started' do
      include_context 'when code tracker is running'

      context 'when a file is required' do
        it 'requests to install pending line probes' do
          expect(Datadog::DI).to receive(:current_component).and_return(component)
          expect(probe_manager).to receive(:install_pending_line_probes) do |path|
            # Should be an absolute path
            expect(path).to start_with('/')
            expect(File.basename(path)).to eq('code_tracker_pending_require.rb')
          end
          require_relative 'code_tracker_pending_require'
        end
      end

      context 'when a file is loaded' do
        it 'requests to install pending line probes' do
          expect(Datadog::DI).to receive(:current_component).and_return(component)
          expect(probe_manager).to receive(:install_pending_line_probes) do |path|
            # Should be an absolute path
            expect(path).to start_with('/')
            expect(File.basename(path)).to eq('code_tracker_pending_load.rb')
          end
          load File.join(File.dirname(__FILE__), 'code_tracker_pending_load.rb')
        end
      end

      context "when Ruby code is eval'd" do
        it 'requests to install pending line probes' do
          # Matchers can be lazily loaded, force all code to be loaded here.
          expect(4).to eq(4)

          expect(Datadog::DI).not_to receive(:current_component)
          expect(probe_manager).not_to receive(:install_pending_line_probes)
          expect(eval('2 + 2')).to eq(4) # rubocop:disable Style/EvalWithLocation
        end
      end
    end
  end

  describe '#backfill_registry' do
    let(:whole_file_iseq) do
      instance_double(RubyVM::InstructionSequence,
        absolute_path: '/app/lib/foo.rb',
        first_lineno: 0,)
    end

    let(:per_method_iseq) do
      instance_double(RubyVM::InstructionSequence,
        absolute_path: '/app/lib/foo.rb',
        first_lineno: 10,)
    end

    let(:eval_iseq) do
      instance_double(RubyVM::InstructionSequence,
        absolute_path: nil,
        first_lineno: 1,)
    end

    # On Ruby 3.1+ iseq_type exists natively; on older Rubies
    # backfill_registry falls back to first_lineno == 0.
    # Only stub iseq_type when it actually exists — RSpec's
    # verify_partial_doubles rejects stubs on nonexistent methods.
    before do
      allow(Datadog::DI).to receive(:respond_to?).and_call_original
      if Datadog::DI.respond_to?(:iseq_type)
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(true)
        # Stub iseq_type to return :top for whole-file iseqs (first_lineno == 0)
        # and :method for per-method iseqs. Cannot use and_call_original because
        # the C function expects a real RubyVM::InstructionSequence, not a double.
        allow(Datadog::DI).to receive(:iseq_type) do |iseq|
          (iseq.first_lineno == 0) ? :top : :method
        end
      else
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)
      end
    end

    after do
      tracker.stop
    end

    it 'populates registry with whole-file iseqs' do
      allow(Datadog::DI).to receive(:file_iseqs).and_return([whole_file_iseq])

      expect(tracker.send(:registry)).to be_empty
      tracker.backfill_registry

      registry = tracker.send(:registry)
      expect(registry.length).to eq(1)
      expect(registry['/app/lib/foo.rb']).to equal(whole_file_iseq)
    end

    it 'skips per-method iseqs' do
      allow(Datadog::DI).to receive(:file_iseqs).and_return([per_method_iseq])

      tracker.backfill_registry

      expect(tracker.send(:registry)).to be_empty
    end

    it 'skips eval iseqs (nil absolute_path)' do
      allow(Datadog::DI).to receive(:file_iseqs).and_return([eval_iseq])

      tracker.backfill_registry

      expect(tracker.send(:registry)).to be_empty
    end

    it 'does not overwrite entries from script_compiled' do
      tracker.start
      load File.join(File.dirname(__FILE__), "code_tracker_load_class.rb")

      path = tracker.send(:registry).keys.find { |p| p.end_with?('code_tracker_load_class.rb') }
      expect(path).not_to be_nil
      original_iseq = tracker.send(:registry)[path]

      # file_iseqs returns an iseq for the same path
      conflicting_iseq = instance_double(RubyVM::InstructionSequence,
        absolute_path: path,
        first_lineno: 0,)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([conflicting_iseq])

      tracker.backfill_registry

      expect(tracker.send(:registry)[path]).to equal(original_iseq)
    end

    it 'stores multiple files from a single backfill call' do
      iseq_a = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/a.rb', first_lineno: 0)
      iseq_b = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/b.rb', first_lineno: 0)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq_a, iseq_b])

      tracker.backfill_registry

      registry = tracker.send(:registry)
      expect(registry.length).to eq(2)
      expect(registry['/app/lib/a.rb']).to equal(iseq_a)
      expect(registry['/app/lib/b.rb']).to equal(iseq_b)
    end

    it 'is idempotent when called twice with the same iseqs' do
      allow(Datadog::DI).to receive(:file_iseqs).and_return([whole_file_iseq])

      tracker.backfill_registry
      tracker.backfill_registry

      registry = tracker.send(:registry)
      expect(registry.length).to eq(1)
      expect(registry['/app/lib/foo.rb']).to equal(whole_file_iseq)
    end

    it 'adds new files on second call without overwriting existing entries' do
      iseq_a = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/a.rb', first_lineno: 0)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq_a])

      tracker.backfill_registry

      # Second call returns the original file plus a new one
      iseq_a_new = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/a.rb', first_lineno: 0)
      iseq_b = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/b.rb', first_lineno: 0)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq_a_new, iseq_b])

      tracker.backfill_registry

      registry = tracker.send(:registry)
      expect(registry.length).to eq(2)
      expect(registry['/app/lib/a.rb']).to equal(iseq_a)
      expect(registry['/app/lib/b.rb']).to equal(iseq_b)
    end

    it 'filters mixed iseq types from a single file' do
      # file_iseqs returns both whole-file and per-method iseqs for same file
      allow(Datadog::DI).to receive(:file_iseqs).and_return(
        [whole_file_iseq, per_method_iseq],
      )

      tracker.backfill_registry

      registry = tracker.send(:registry)
      expect(registry.length).to eq(1)
      # The whole-file iseq should be stored (first_lineno == 0)
      expect(registry['/app/lib/foo.rb']).to equal(whole_file_iseq)
    end

    context 'when file_iseqs raises an exception' do
      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_raise(RuntimeError, 'object space walk failed')
      end

      it 'does not propagate the exception' do
        expect { tracker.backfill_registry }.not_to raise_error
      end

      it 'leaves registry unchanged' do
        tracker.backfill_registry
        expect(tracker.send(:registry)).to be_empty
      end

      context 'when component is available' do
        let(:component) do
          instance_double(Datadog::DI::Component).tap do |component|
            allow(component).to receive(:logger).and_return(logger)
            allow(component).to receive(:telemetry).and_return(telemetry)
          end
        end

        let(:logger) do
          instance_double(Datadog::DI::Logger).tap do |logger|
            allow(logger).to receive(:debug)
          end
        end

        let(:telemetry) do
          instance_double(Datadog::Core::Telemetry::Component).tap do |telemetry|
            allow(telemetry).to receive(:report)
          end
        end

        before do
          allow(Datadog::DI).to receive(:current_component).and_return(component)
        end

        it 'logs the error at debug level' do
          tracker.backfill_registry

          expect(logger).to have_received(:debug) do |&block|
            expect(block.call).to match(/backfill_registry failed.*RuntimeError.*object space walk failed/)
          end
        end

        it 'reports the error via telemetry' do
          tracker.backfill_registry

          expect(telemetry).to have_received(:report).with(
            an_instance_of(RuntimeError),
            hash_including(description: "backfill_registry failed"),
          )
        end
      end
    end

    context 'when iseq_type is not available' do
      before do
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)
      end

      it 'falls back to first_lineno == 0 for whole-file detection' do
        allow(Datadog::DI).to receive(:file_iseqs).and_return(
          [whole_file_iseq, per_method_iseq],
        )

        tracker.backfill_registry

        registry = tracker.send(:registry)
        expect(registry.length).to eq(1)
        expect(registry['/app/lib/foo.rb']).to equal(whole_file_iseq)
      end

      it 'skips iseqs with non-zero first_lineno' do
        allow(Datadog::DI).to receive(:file_iseqs).and_return([per_method_iseq])

        tracker.backfill_registry

        expect(tracker.send(:registry)).to be_empty
      end
    end
  end

  describe '#start calls backfill_registry' do
    after do
      tracker.stop
    end

    it 'calls backfill_registry during start' do
      expect(tracker).to receive(:backfill_registry)
      tracker.start
    end

    it 'tracker is active after start calls backfill_registry' do
      allow(tracker).to receive(:backfill_registry)
      tracker.start
      expect(tracker.active?).to be true
    end
  end

  describe '#iseqs_for_path_suffix with backfilled entries' do
    before do
      allow(Datadog::DI).to receive(:respond_to?).and_call_original
      if Datadog::DI.respond_to?(:iseq_type)
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(true)
        # Stub iseq_type to return :top for whole-file iseqs (first_lineno == 0)
        # and :method for per-method iseqs. Cannot use and_call_original because
        # the C function expects a real RubyVM::InstructionSequence, not a double.
        allow(Datadog::DI).to receive(:iseq_type) do |iseq|
          (iseq.first_lineno == 0) ? :top : :method
        end
      else
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)
      end
    end

    after do
      tracker.stop
    end

    it 'finds backfilled entries by suffix' do
      iseq = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/datadog/di/foo.rb', first_lineno: 0)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq])

      tracker.backfill_registry

      result = tracker.iseqs_for_path_suffix('di/foo.rb')
      expect(result).to eq(['/app/lib/datadog/di/foo.rb', iseq])
    end

    it 'finds backfilled entries by exact path' do
      iseq = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/datadog/di/foo.rb', first_lineno: 0)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq])

      tracker.backfill_registry

      result = tracker.iseqs_for_path_suffix('/app/lib/datadog/di/foo.rb')
      expect(result).to eq(['/app/lib/datadog/di/foo.rb', iseq])
    end

    it 'returns nil for paths not in backfill' do
      allow(Datadog::DI).to receive(:file_iseqs).and_return([])

      tracker.backfill_registry

      expect(tracker.iseqs_for_path_suffix('nonexistent.rb')).to be_nil
    end
  end

  describe "#iseqs_for_path_suffix" do
    around do |example|
      # Stub backfill so we only have the 4 explicitly loaded files.
      # Use define_method to avoid rspec allow/receive scoping issues
      # inside around blocks.
      tracker.define_singleton_method(:backfill_registry) {}
      tracker.start

      load File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_class_2.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_class_3.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_classes", "code_tracker_test_class_1.rb")
      expect(tracker.send(:registry).each.to_a.length).to eq(4)

      # To be able to assert on the registry, replace values (iseqs)
      # with the keys.
      (registry = tracker.send(:registry)).each do |k, v|
        registry[k] = k
      end

      example.run

      tracker.stop
    end

    context "exact match for full path" do
      let(:path) do
        File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb")
      end

      it "returns the exact match only" do
        expect(tracker.iseqs_for_path_suffix(path)).to eq([path, path])
      end
    end

    context "basename matches two paths" do
      let(:expected) do
        [
          File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb"),
          File.join(File.dirname(__FILE__), "code_tracker_test_classes", "code_tracker_test_class_1.rb"),
        ]
      end

      it "raises exception" do
        expect do
          tracker.iseqs_for_path_suffix("code_tracker_test_class_1.rb")
        end.to raise_error(Datadog::DI::Error::MultiplePathsMatch)
      end
    end

    context "match not on path component boundary" do
      it "returns nil" do
        expect(tracker.iseqs_for_path_suffix("1.rb")).to be nil
      end
    end
  end

  describe '#iseq_for_line' do
    before do
      allow(Datadog::DI).to receive(:respond_to?).and_call_original
      allow(Datadog::DI).to receive(:respond_to?).with(:all_iseqs).and_return(true)
      # Only stub iseq_type when it actually exists — RSpec's partial double
      # verification rejects stubs for undefined methods (Ruby < 3.1).
      if Datadog::DI.respond_to?(:iseq_type)
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(true)
        allow(Datadog::DI).to receive(:iseq_type) do |iseq|
          (iseq.first_lineno == 0) ? :top : :method
        end
      else
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)
      end
    end

    after do
      tracker.stop
    end

    context 'when whole-file iseq exists' do
      it 'returns the whole-file iseq' do
        iseq = instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/foo.rb',
          first_lineno: 0,)
        allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq])

        tracker.backfill_registry

        result = tracker.iseq_for_line('foo.rb', 10)
        expect(result).to eq(['/app/lib/foo.rb', iseq])
      end
    end

    context 'when only per-method iseqs exist' do
      let(:method_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/bar.rb',
          first_lineno: 5,
          trace_points: [[5, :line], [6, :line], [7, :line], [8, :return]],)
      end

      let(:other_method_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/bar.rb',
          first_lineno: 20,
          trace_points: [[20, :line], [21, :line], [22, :return]],)
      end

      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return(
          [method_iseq, other_method_iseq],
        )
        tracker.backfill_registry
      end

      it 'returns per-method iseq covering the target line' do
        result = tracker.iseq_for_line('bar.rb', 6)
        expect(result).to eq(['/app/lib/bar.rb', method_iseq])
      end

      it 'returns different iseq for line in a different method' do
        result = tracker.iseq_for_line('bar.rb', 21)
        expect(result).to eq(['/app/lib/bar.rb', other_method_iseq])
      end

      it 'returns nil when no iseq covers the target line' do
        result = tracker.iseq_for_line('bar.rb', 15)
        expect(result).to be_nil
      end
    end

    context 'when per-method iseq has only :call event at target line' do
      let(:call_only_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/bar.rb',
          first_lineno: 10,
          trace_points: [[10, :call], [11, :line], [12, :line]],)
      end

      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return([call_only_iseq])
        tracker.backfill_registry
      end

      it 'returns nil for call-only line' do
        result = tracker.iseq_for_line('bar.rb', 10)
        expect(result).to be_nil
      end

      it 'returns iseq for line with :line event' do
        result = tracker.iseq_for_line('bar.rb', 11)
        expect(result).to eq(['/app/lib/bar.rb', call_only_iseq])
      end
    end

    context 'when no iseqs exist at all' do
      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return([])
        tracker.backfill_registry
      end

      it 'returns nil' do
        result = tracker.iseq_for_line('missing.rb', 10)
        expect(result).to be_nil
      end
    end

    context 'with path suffix matching for per-method iseqs' do
      let(:method_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/datadog/di/baz.rb',
          first_lineno: 10,
          trace_points: [[10, :line], [11, :line]],)
      end

      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return([method_iseq])
        tracker.backfill_registry
      end

      it 'resolves suffix to per-method iseq' do
        result = tracker.iseq_for_line('di/baz.rb', 10)
        expect(result).to eq(['/app/lib/datadog/di/baz.rb', method_iseq])
      end

      it 'resolves exact path to per-method iseq' do
        result = tracker.iseq_for_line('/app/lib/datadog/di/baz.rb', 11)
        expect(result).to eq(['/app/lib/datadog/di/baz.rb', method_iseq])
      end
    end

    context 'when multiple per-method iseqs match the same line' do
      let(:method_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/qux.rb',
          first_lineno: 10,
          trace_points: [[10, :line], [11, :line]],)
      end

      let(:block_iseq) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/qux.rb',
          first_lineno: 10,
          trace_points: [[10, :line], [11, :line]],)
      end

      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return(
          [method_iseq, block_iseq],
        )
        tracker.backfill_registry
      end

      it 'raises MultiplePathsMatch for ambiguous line' do
        expect do
          tracker.iseq_for_line('qux.rb', 10)
        end.to raise_error(Datadog::DI::Error::MultiplePathsMatch, /Multiple code locations/)
      end
    end

    context 'when per-method path suffix matches multiple paths' do
      let(:iseq_a) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/foo/target.rb',
          first_lineno: 5,
          trace_points: [[5, :line]],)
      end

      let(:iseq_b) do
        instance_double(RubyVM::InstructionSequence,
          absolute_path: '/app/lib/bar/target.rb',
          first_lineno: 5,
          trace_points: [[5, :line]],)
      end

      before do
        allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq_a, iseq_b])
        tracker.backfill_registry
      end

      it 'raises MultiplePathsMatch for ambiguous suffix' do
        expect do
          tracker.iseq_for_line('target.rb', 5)
        end.to raise_error(Datadog::DI::Error::MultiplePathsMatch)
      end
    end
  end

  describe '#backfill_registry stores per-method iseqs' do
    before do
      allow(Datadog::DI).to receive(:respond_to?).and_call_original
      allow(Datadog::DI).to receive(:respond_to?).with(:all_iseqs).and_return(true)
      # Only stub iseq_type when it actually exists — RSpec's partial double
      # verification rejects stubs for undefined methods (Ruby < 3.1).
      if Datadog::DI.respond_to?(:iseq_type)
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(true)
        allow(Datadog::DI).to receive(:iseq_type) do |iseq|
          (iseq.first_lineno == 0) ? :top : :method
        end
      else
        allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)
      end
    end

    after do
      tracker.stop
    end

    it 'stores per-method iseqs in per_method_registry' do
      method_iseq = instance_double(RubyVM::InstructionSequence,
        absolute_path: '/app/lib/foo.rb',
        first_lineno: 10,
        trace_points: [[10, :line]],)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([method_iseq])

      tracker.backfill_registry

      per_method = tracker.send(:per_method_registry)
      expect(per_method['/app/lib/foo.rb']).to eq([method_iseq])
    end

    it 'groups multiple per-method iseqs by path' do
      iseq_a = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/foo.rb', first_lineno: 5)
      iseq_b = instance_double(RubyVM::InstructionSequence, absolute_path: '/app/lib/foo.rb', first_lineno: 20)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([iseq_a, iseq_b])

      tracker.backfill_registry

      per_method = tracker.send(:per_method_registry)
      expect(per_method['/app/lib/foo.rb']).to eq([iseq_a, iseq_b])
    end

    it 'excludes compile_file :top iseqs from per_method_registry' do
      next skip "iseq_type not available on Ruby < 3.1" unless Datadog::DI.respond_to?(:iseq_type)

      compile_file_iseq = instance_double(RubyVM::InstructionSequence,
        absolute_path: '/app/lib/foo.rb',
        first_lineno: 1,)
      # Override the default iseq_type stub to return :top for this
      # specific iseq, simulating a compile_file-produced :top iseq.
      allow(Datadog::DI).to receive(:iseq_type).with(compile_file_iseq).and_return(:top)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([compile_file_iseq])

      tracker.backfill_registry

      expect(tracker.send(:per_method_registry)).to be_empty
      expect(tracker.send(:registry)).to be_empty
    end

    it 'clear removes per-method iseqs' do
      method_iseq = instance_double(RubyVM::InstructionSequence,
        absolute_path: '/app/lib/foo.rb',
        first_lineno: 10,)
      allow(Datadog::DI).to receive(:file_iseqs).and_return([method_iseq])

      tracker.backfill_registry
      tracker.clear

      expect(tracker.send(:per_method_registry)).to be_empty
    end
  end
end
