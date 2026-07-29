require "datadog/di/spec_helper"
require "datadog/di/correlation"
require "datadog/di/execution_unit"

RSpec.describe Datadog::DI::Correlation do
  di_test

  subject(:correlation) { described_class.new(max_entries: max_entries) }

  let(:max_entries) { 4096 }

  # A probe whose rate limiter admits +allow+ times, then denies. nil limiter
  # means "always allow" (matches a probe constructed with no rate limit).
  def probe_double(id, allow: Float::INFINITY, limiter: :default)
    rate_limiter =
      if limiter == :default
        remaining = allow
        double("rate_limiter").tap do |rl|
          allow(rl).to receive(:allow?) do
            if remaining > 0
              remaining -= 1
              true
            else
              false
            end
          end
        end
      else
        limiter
      end
    double("probe", id: id, rate_limiter: rate_limiter)
  end

  def unit(key, scope = key, source: :apm)
    Datadog::DI::ExecutionUnit.new(key, scope, source)
  end

  def none_unit
    Datadog::DI::ExecutionUnit.new(nil, nil, :none)
  end

  describe "#emit?" do
    context "within an execution unit" do
      it "emits when the deciding probe's limiter admits" do
        expect(correlation.emit?(probe_double("a", allow: 1), unit("u1", "s1"))).to be(true)
      end

      it "drops the whole unit when the deciding probe's limiter denies" do
        expect(correlation.emit?(probe_double("a", allow: 0), unit("u1", "s1"))).to be(false)
      end

      it "shares one decision across sibling probes in the same unit" do
        # First probe decides EMIT for the unit.
        expect(correlation.emit?(probe_double("a", allow: 1), unit("u1", "s1"))).to be(true)
        # Sibling probe with a denying limiter still inherits EMIT (its limiter
        # is not consulted), then emits once under its own cap slot.
        sibling = probe_double("b", allow: 0)
        expect(correlation.emit?(sibling, unit("u1", "s1"))).to be(true)
      end

      it "propagates a drop decision to sibling probes" do
        expect(correlation.emit?(probe_double("a", allow: 0), unit("u1", "s1"))).to be(false)
        # Sibling whose own limiter would admit still inherits DROP.
        expect(correlation.emit?(probe_double("b", allow: 1), unit("u1", "s1"))).to be(false)
      end

      describe "per-probe-per-scope cap" do
        it "admits a probe once per scope, then suppresses repeats" do
          probe = probe_double("a", allow: 5)
          expect(correlation.emit?(probe, unit("u1", "s1"))).to be(true)
          expect(correlation.emit?(probe, unit("u1", "s1"))).to be(false)
          expect(correlation.emit?(probe, unit("u1", "s1"))).to be(false)
        end

        it "does not let one probe's cap affect another probe" do
          correlation.emit?(probe_double("a", allow: 1), unit("u1", "s1")) # decides EMIT
          expect(correlation.emit?(probe_double("a", allow: 5), unit("u1", "s1"))).to be(false) # a capped
          expect(correlation.emit?(probe_double("b", allow: 5), unit("u1", "s1"))).to be(true) # b fresh
        end

        it "resets the cap for a different scope" do
          probe = probe_double("a", allow: 5)
          expect(correlation.emit?(probe, unit("u1", "s1"))).to be(true)
          expect(correlation.emit?(probe, unit("u1", "s1"))).to be(false)
          expect(correlation.emit?(probe, unit("u1", "s2"))).to be(true)
        end
      end
    end

    context "no execution unit" do
      it "makes an independent per-probe decision" do
        expect(correlation.emit?(probe_double("a", allow: 1), none_unit)).to be(true)
        expect(correlation.emit?(probe_double("a", allow: 0), none_unit)).to be(false)
      end

      it "does not cache decisions across independent hits" do
        # Same probe, its limiter admits twice: both independent hits emit
        # (no unit to coordinate).
        probe = probe_double("a", allow: 2)
        expect(correlation.emit?(probe, none_unit)).to be(true)
        expect(correlation.emit?(probe, none_unit)).to be(true)
      end
    end

    describe "cap-scope LRU eviction" do
      let(:max_entries) { 2 }

      it "evicts the oldest scope, resetting its cap" do
        probe = probe_double("a", allow: 100)
        expect(correlation.emit?(probe, unit("u", "s1"))).to be(true)
        expect(correlation.emit?(probe, unit("u", "s1"))).to be(false) # s1 caps a

        correlation.emit?(probe, unit("u", "s2"))
        correlation.emit?(probe, unit("u", "s3")) # inserting s3 evicts s1

        # s1 was evicted, so its cap has reset and a may emit again.
        expect(correlation.emit?(probe, unit("u", "s1"))).to be(true)
      end
    end
  end
end
