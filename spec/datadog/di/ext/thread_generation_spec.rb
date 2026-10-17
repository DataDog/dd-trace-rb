require "datadog/di/spec_helper"

# Unit tests for the C-implemented snapshot generation token primitive:
# Datadog::DI.current_thread_generation. These tests exercise the token's
# semantics: a positive integer, stable for one thread, shared by all fibers
# of a thread, distinct across threads, and still assigned to a Thread
# frozen before its first snapshot.

RSpec.describe "Datadog::DI snapshot generation token" do
  di_test
  describe ".current_thread_generation" do
    context "for the calling thread" do
      let(:token) { Datadog::DI.current_thread_generation }

      before do
        expect(token).to be_a(Integer)
        expect(token).to be > 0
      end

      it "returns a positive integer" do
        expect(token).to be_a(Integer)
        expect(token).to be > 0
      end

      it "returns the same token across calls" do
        expect(Datadog::DI.current_thread_generation).to eq(token)
      end

      it "returns the same token to all fibers of the thread" do
        fiber_token = nil
        Fiber.new { fiber_token = Datadog::DI.current_thread_generation }.resume

        expect(fiber_token).to eq(token)
      end
    end

    context "for a different thread" do
      let(:calling_thread_token) { Datadog::DI.current_thread_generation }

      before do
        expect(calling_thread_token).to be_a(Integer)
        expect(calling_thread_token).to be > 0
      end

      it "returns a token distinct from the calling thread's token" do
        other_token = nil
        thread = Thread.new { other_token = Datadog::DI.current_thread_generation }
        raise "thread wait timeout" unless thread.join(5)

        expect(other_token).to be_a(Integer)
        expect(other_token).not_to eq(calling_thread_token)
      end

      it "returns the same token across calls within the thread" do
        tokens = []
        thread = Thread.new { 3.times { tokens << Datadog::DI.current_thread_generation } }
        raise "thread wait timeout" unless thread.join(5)

        expect(tokens.first).to be_a(Integer)
        expect(tokens.uniq).to eq([tokens.first])
      end
    end

    context "for a thread frozen before its first token" do
      it "returns a positive integer" do
        token = nil
        thread = Thread.new do
          Thread.current.freeze
          token = Datadog::DI.current_thread_generation
        end
        raise "thread wait timeout" unless thread.join(5)

        expect(token).to be_a(Integer)
        expect(token).to be > 0
      end

      it "returns the same token across calls within the thread" do
        tokens = []
        thread = Thread.new do
          Thread.current.freeze
          3.times { tokens << Datadog::DI.current_thread_generation }
        end
        raise "thread wait timeout" unless thread.join(5)

        expect(tokens.first).to be_a(Integer)
        expect(tokens.uniq).to eq([tokens.first])
      end

      it "returns a token distinct from the calling thread's token" do
        frozen_thread_token = nil
        thread = Thread.new do
          Thread.current.freeze
          frozen_thread_token = Datadog::DI.current_thread_generation
        end
        raise "thread wait timeout" unless thread.join(5)

        expect(frozen_thread_token).to be_a(Integer)
        expect(frozen_thread_token).not_to eq(Datadog::DI.current_thread_generation)
      end
    end

    context "for a thread frozen after its first token" do
      it "keeps returning the token assigned before the freeze" do
        tokens = []
        thread = Thread.new do
          tokens << Datadog::DI.current_thread_generation
          Thread.current.freeze
          tokens << Datadog::DI.current_thread_generation
        end
        raise "thread wait timeout" unless thread.join(5)

        expect(tokens.uniq).to eq([tokens.first])
      end
    end
  end
end
