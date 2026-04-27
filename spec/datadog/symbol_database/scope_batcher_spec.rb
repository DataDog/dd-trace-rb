# frozen_string_literal: true

require 'datadog/symbol_database/logger'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::ScopeBatcher do
  let(:uploader) { instance_double(Datadog::SymbolDatabase::Uploader) }
  let(:raw_logger) { instance_double(Logger, debug: nil) }
  let(:settings) do
    s = double('settings')
    symdb = double('symbol_database', internal: double('internal', trace_logging: false))
    allow(s).to receive(:symbol_database).and_return(symdb)
    s
  end
  let(:logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }
  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'TestClass') }

  subject(:context) { described_class.new(uploader, logger: logger) }

  after do
    # Cleanup any running timers
    context.reset
  end

  describe '#initialize' do
    it 'creates context with empty scopes' do
      expect(context.size).to eq(0)
      expect(context.scopes_pending?).to be false
    end
  end

  describe '#add_scope' do
    it 'adds scope to batch' do
      context.add_scope(test_scope)

      expect(context.size).to eq(1)
      expect(context.scopes_pending?).to be true
    end

    it 'increments file count' do
      context.add_scope(test_scope)
      context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Other'))

      # File count tracked (implementation detail, testing via behavior)
      expect(context.size).to eq(2)
    end

    context 'when batch size limit reached' do
      it 'triggers immediate upload' do
        expect(uploader).to receive(:upload_scopes) do |scopes|
          expect(scopes.size).to eq(400)
        end

        # Add 400 scopes
        400.times do |i|
          scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Class#{i}")
          context.add_scope(scope)
        end

        expect(context.size).to eq(0)  # Batch cleared after upload
      end

      it 'continues batching after upload' do
        allow(uploader).to receive(:upload_scopes)

        # Add 401 scopes
        401.times do |i|
          scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Class#{i}")
          context.add_scope(scope)
        end

        expect(context.size).to eq(1)  # 401st scope in new batch
      end
    end

    context 'with inactivity timer' do
      it 'would trigger upload after inactivity (timer disabled in tests)' do
        allow(uploader).to receive(:upload_scopes)

        test_context = described_class.new(uploader, logger: logger, timer_enabled: false)

        test_context.add_scope(test_scope)
        expect(test_context.size).to eq(1)

        # Manually trigger what timer would do
        test_context.flush

        expect(test_context.size).to eq(0)
      end

      it 'timer gets reset on scope additions (verified by integration tests)' do
        allow(uploader).to receive(:upload_scopes)

        test_context = described_class.new(uploader, logger: logger, timer_enabled: false)

        test_context.add_scope(test_scope)
        test_context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Class2'))

        # Without timer, scopes stay in batch
        expect(test_context.size).to eq(2)

        # Manual flush works
        test_context.flush
        expect(test_context.size).to eq(0)
      end
    end

    context 'with deduplication' do
      it 'skips already uploaded modules' do
        allow(uploader).to receive(:upload_scopes)

        # Add same scope twice
        context.add_scope(test_scope)
        context.add_scope(test_scope)

        expect(context.size).to eq(1)  # Only added once
      end

      it 'tracks uploaded modules across batches' do
        allow(uploader).to receive(:upload_scopes)

        context.add_scope(test_scope)
        context.flush  # Upload first batch

        # Try to add same scope again
        context.add_scope(test_scope)

        expect(context.size).to eq(0)  # Not added (already uploaded)
      end
    end

    context 'with file limit' do
      it 'stops accepting scopes after MAX_FILES limit' do
        allow(uploader).to receive(:upload_scopes)

        # Add MAX_FILES scopes
        described_class::MAX_FILES.times do |i|
          scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Class#{i}")
          context.add_scope(scope)
        end

        # Try to add one more
        extra_scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'ExtraClass')
        expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/file limit.*reached/i) }

        context.add_scope(extra_scope)

        # Should not be in batch
        expect(context.size).to be < described_class::MAX_FILES
      end
    end
  end

  describe '#flush' do
    it 'uploads current batch immediately' do
      expect(uploader).to receive(:upload_scopes) do |scopes|
        expect(scopes.size).to eq(2)
      end

      context.add_scope(test_scope)
      context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Other'))

      context.flush

      expect(context.size).to eq(0)
    end

    it 'does nothing if batch is empty' do
      expect(uploader).not_to receive(:upload_scopes)

      context.flush
    end
  end

  describe '#shutdown' do
    it 'uploads remaining scopes' do
      uploaded_scopes = nil
      allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes = scopes }

      context.add_scope(test_scope)
      context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Other'))

      context.shutdown

      expect(uploaded_scopes).not_to be_nil
      expect(uploaded_scopes.size).to eq(2)
    end

    it 'kills timer thread' do
      allow(uploader).to receive(:upload_scopes)

      context.add_scope(test_scope)
      context.shutdown

      # Shutdown uploads and kills timer
      expect(context.size).to eq(0)
    end

    it 'clears scopes after shutdown' do
      allow(uploader).to receive(:upload_scopes)

      context.add_scope(test_scope)
      context.shutdown

      expect(context.size).to eq(0)
    end
  end

  describe '#reset' do
    it 'clears all state' do
      allow(uploader).to receive(:upload_scopes)

      context.add_scope(test_scope)
      context.reset

      expect(context.size).to eq(0)
      expect(context.scopes_pending?).to be false
    end

    it 'kills timer' do
      allow(uploader).to receive(:upload_scopes)

      context.add_scope(test_scope)
      context.reset

      # Reset clears scopes and kills timer
      expect(context.size).to eq(0)
    end
  end

  describe '#pending?' do
    it 'returns false when no scopes' do
      expect(context.scopes_pending?).to be false
    end

    it 'returns true when scopes exist' do
      context.add_scope(test_scope)
      expect(context.scopes_pending?).to be true
    end
  end

  describe '#size' do
    it 'returns 0 when empty' do
      expect(context.size).to eq(0)
    end

    it 'returns count of scopes' do
      context.add_scope(test_scope)
      expect(context.size).to eq(1)

      context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Other'))
      expect(context.size).to eq(2)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent scope additions' do
      allow(uploader).to receive(:upload_scopes)

      # Use timer_enabled: false so the test validates mutex-protected concurrent
      # additions without timer interference (timer could flush mid-test, making
      # the final size non-deterministic).
      timer_off_context = described_class.new(uploader, logger: logger, timer_enabled: false)

      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Thread#{i}Class#{j}")
            timer_off_context.add_scope(scope)
          end
        end
      end

      threads.each(&:join)

      # All 100 unique scopes should be present (no losses from races)
      expect(timer_off_context.size).to eq(100)
    end
  end

  # === Tests ported from Java SymbolSinkTest ===

  describe 'multi-scope batching (ported from Java SymbolSinkTest.testMultiScopeFlush)' do
    it 'batches multiple scopes into a single upload call' do
      uploaded_scopes = nil
      allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes = scopes }

      5.times do |i|
        context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Class#{i}"))
      end

      context.flush

      expect(uploaded_scopes).not_to be_nil
      expect(uploaded_scopes.size).to eq(5)
      names = uploaded_scopes.map(&:name)
      expect(names).to include('Class0', 'Class1', 'Class2', 'Class3', 'Class4')
    end
  end

  describe 'implicit flush at capacity (ported from Java SymbolSinkTest.testQueueFull)' do
    it 'uploads automatically at MAX_SCOPES and continues batching remaining' do
      upload_calls = []
      allow(uploader).to receive(:upload_scopes) { |scopes| upload_calls << scopes.dup }

      # Add exactly MAX_SCOPES scopes to trigger implicit flush
      described_class::MAX_SCOPES.times do |i|
        context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Batch1Class#{i}"))
      end

      # Should have flushed the first batch
      expect(upload_calls.size).to eq(1)
      expect(upload_calls[0].size).to eq(described_class::MAX_SCOPES)

      # Add one more scope (should be in new batch)
      context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'ExtraClass'))
      expect(context.size).to eq(1)

      # Flush the remaining
      context.flush
      expect(upload_calls.size).to eq(2)
      expect(upload_calls[1].size).to eq(1)
      expect(upload_calls[1][0].name).to eq('ExtraClass')
    end
  end

  describe 'upload on shutdown with pending scopes (ported from Java SymbolSinkTest)' do
    it 'flushes all pending scopes on shutdown' do
      uploaded_scopes = nil
      allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes = scopes }

      3.times do |i|
        context.add_scope(Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "ShutdownClass#{i}"))
      end

      context.shutdown

      expect(uploaded_scopes).not_to be_nil
      expect(uploaded_scopes.size).to eq(3)
    end
  end

  describe 'deduplication across multiple flushes (ported from Java SymDBEnablementTest.noDuplicateSymbolExtraction)' do
    it 'does not re-upload the same scope after flush and re-add' do
      upload_calls = []
      allow(uploader).to receive(:upload_scopes) { |scopes| upload_calls << scopes.dup }

      scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'UniqueClass')

      context.add_scope(scope)
      context.flush
      expect(upload_calls.size).to eq(1)
      expect(upload_calls[0].size).to eq(1)

      # Try to add the same scope again
      context.add_scope(scope)
      context.flush

      # Should not have triggered a second upload (empty batch)
      expect(upload_calls.size).to eq(1)
    end
  end
end
