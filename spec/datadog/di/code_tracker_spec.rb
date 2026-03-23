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
      tracker.start
    end

    after do
      tracker.stop
    end
  end

  describe "#start" do
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
    after do
      tracker.stop
    end

    context 'when C extension is available' do
      before do
        skip 'C extension not available' unless Datadog::DI.respond_to?(:all_iseqs)
      end

      it 'populates registry with iseqs for already-loaded files' do
        # The registry should be empty before backfill.
        expect(tracker.send(:registry)).to be_empty

        tracker.backfill_registry

        registry = tracker.send(:registry)
        expect(registry).not_to be_empty

        # All entries should have absolute paths as keys
        registry.each_key do |path|
          expect(path).to start_with('/')
        end

        # All entries should be instruction sequences
        registry.each_value do |iseq|
          expect(iseq).to be_a(RubyVM::InstructionSequence)
        end

        # Should contain iseqs for dd-trace-rb files that are already loaded
        datadog_paths = registry.keys.select { |p| p.include?('lib/datadog/') }
        expect(datadog_paths).not_to be_empty
      end

      it 'only stores whole-file iseqs' do
        tracker.backfill_registry

        registry = tracker.send(:registry)
        registry.each_value do |iseq|
          expect(iseq.first_lineno).to eq(0),
            "Expected whole-file iseq (first_lineno=0) but got first_lineno=#{iseq.first_lineno} for #{iseq.absolute_path}"
        end
      end

      it 'does not overwrite entries from script_compiled' do
        # Start tracking to populate registry via :script_compiled
        tracker.start
        load File.join(File.dirname(__FILE__), "code_tracker_load_class.rb")

        path = tracker.send(:registry).keys.find { |p| p.end_with?('code_tracker_load_class.rb') }
        expect(path).not_to be_nil
        original_iseq = tracker.send(:registry)[path]

        # Backfill should not overwrite the existing entry
        tracker.backfill_registry
        expect(tracker.send(:registry)[path]).to equal(original_iseq)
      end
    end

    context 'when C extension is not available' do
      before do
        allow(Datadog::DI).to receive(:respond_to?).and_call_original
        allow(Datadog::DI).to receive(:respond_to?).with(:all_iseqs).and_return(false)
      end

      it 'does nothing' do
        expect(tracker.send(:registry)).to be_empty
        tracker.backfill_registry
        expect(tracker.send(:registry)).to be_empty
      end
    end
  end

  describe '#start with backfill' do
    after do
      tracker.stop
    end

    context 'when C extension is available' do
      before do
        skip 'C extension not available' unless Datadog::DI.respond_to?(:all_iseqs)
      end

      it 'backfills registry on start' do
        tracker.start

        registry = tracker.send(:registry)
        # Registry should contain backfilled entries (files loaded before start)
        datadog_paths = registry.keys.select { |p| p.include?('lib/datadog/') }
        expect(datadog_paths).not_to be_empty
      end
    end
  end

  describe "#iseqs_for_path_suffix" do
    around do |example|
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
end
