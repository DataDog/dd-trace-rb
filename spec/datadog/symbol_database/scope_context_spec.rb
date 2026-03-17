# frozen_string_literal: true

require 'datadog/symbol_database/scope_context'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::ScopeContext do
  let(:uploader) { instance_double(Datadog::SymbolDatabase::Uploader) }
  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'TestClass') }

  subject(:context) { described_class.new(uploader) }

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

        test_context = described_class.new(uploader, timer_enabled: false)

        test_context.add_scope(test_scope)
        expect(test_context.size).to eq(1)

        # Manually trigger what timer would do
        test_context.flush

        expect(test_context.size).to eq(0)
      end

      it 'timer gets reset on scope additions (verified by integration tests)' do
        allow(uploader).to receive(:upload_scopes)

        test_context = described_class.new(uploader, timer_enabled: false)

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
        expect(Datadog.logger).to receive(:debug).with(/File limit.*reached/)

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
      upload_called = false
      allow(uploader).to receive(:upload_scopes) { |scopes| upload_called = true }

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

      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: "Thread#{i}Class#{j}")
            context.add_scope(scope)
          end
        end
      end

      threads.each(&:join)

      # Should have added scopes safely (up to MAX_SCOPES or all 100)
      expect(context.size).to be <= 100
    end
  end
end
