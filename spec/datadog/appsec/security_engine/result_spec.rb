# frozen_string_literal: true

require "datadog/appsec/spec_helper"

RSpec.describe Datadog::AppSec::SecurityEngine::Result do
  describe "#rule_triggered?" do
    subject(:rule_triggered) { result.rule_triggered? }

    let(:result) do
      result_class.new(
        events: events, actions: actions, attributes: attributes, keep: false, timeout: false,
        duration_ns: 0, duration_ext_ns: 0, input_truncated: false,
      )
    end
    let(:result_class) { described_class::Match }
    let(:events) { [] }
    let(:actions) { {} }
    let(:attributes) { {} }

    it { is_expected.to be(false) }

    context "when a match contains events" do
      let(:events) { [{"rule" => {"id" => "test-rule"}}] }

      it { is_expected.to be(true) }
    end

    context "when a match contains actions" do
      let(:actions) { {"block_request" => {}} }

      it { is_expected.to be(true) }
    end

    context "when a match only contains attributes" do
      let(:attributes) { {"_dd.appsec.fp.http.endpoint" => "fingerprint"} }

      it { is_expected.to be(false) }
    end

    context "when the result is not a match" do
      let(:result_class) { described_class::Ok }
      let(:events) { [{"rule" => {"id" => "test-rule"}}] }
      let(:actions) { {"block_request" => {}} }

      it { is_expected.to be(false) }
    end

    context "when the result is an error" do
      let(:result) { described_class::Error.new(duration_ext_ns: 0, input_truncated: false) }

      it { is_expected.to be(false) }
    end
  end

  describe ".new" do
    context "when initializing non-error result" do
      subject(:result) do
        described_class::Ok.new(
          events: [1],
          actions: {"2" => "2"},
          attributes: {"3" => "3"},
          keep: true,
          timeout: true,
          duration_ns: 400,
          duration_ext_ns: 500,
          input_truncated: false,
        )
      end

      it { expect(result).to be_keep }
      it { expect(result).to be_timeout }
      it { expect(result).not_to be_input_truncated }
      it { expect(result.events).to eq([1]) }
      it { expect(result.actions).to eq({"2" => "2"}) }
      it { expect(result.attributes).to eq({"3" => "3"}) }
      it { expect(result.duration_ns).to eq(400) }
      it { expect(result.duration_ext_ns).to eq(500) }
    end

    context "when initializing error result" do
      subject(:result) { described_class::Error.new(duration_ext_ns: 100, input_truncated: false) }

      it { expect(result).not_to be_keep }
      it { expect(result).not_to be_timeout }
      it { expect(result).not_to be_input_truncated }
      it { expect(result.events).to eq([]) }
      it { expect(result.actions).to eq({}) }
      it { expect(result.attributes).to eq({}) }
      it { expect(result.duration_ns).to eq(0) }
      it { expect(result.duration_ext_ns).to eq(100) }
    end
  end

  describe "#timeout?" do
    context "when result indicates timeout" do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, attributes: {}, timeout: true, duration_ns: 0, duration_ext_ns: 0, keep: false,
          input_truncated: false,
        )
      end

      it { expect(result).to be_timeout }
    end

    context "when result does not indicate timeout" do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, attributes: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0, keep: false,
          input_truncated: false,
        )
      end

      it { expect(result).not_to be_timeout }
    end
  end

  describe "#match?" do
    context "when result is a generic type" do
      subject(:result) do
        described_class::Base.new(
          events: [], actions: {}, attributes: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect { result.match? }.to raise_error NotImplementedError }
    end

    context 'when result is a "match" type' do
      subject(:result) do
        described_class::Match.new(
          events: [], actions: {}, attributes: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0, keep: false,
          input_truncated: false,
        )
      end

      it { expect(result).to be_match }
    end

    context 'when result is an "ok" type' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, attributes: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0, keep: false,
          input_truncated: false,
        )
      end

      it { expect(result).not_to be_match }
    end

    context 'when result is an "error" type' do
      subject(:result) { described_class::Error.new(duration_ext_ns: 0, input_truncated: false) }

      it { expect(result).not_to be_match }
    end
  end

  describe "#error?" do
    context "when result is a generic type" do
      subject(:result) do
        described_class::Base.new(
          events: [], actions: {}, attributes: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect { result.error? }.to raise_error NotImplementedError }
    end

    context 'when result is a "match" type' do
      subject(:result) do
        described_class::Match.new(
          events: [], actions: {}, attributes: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect(result).not_to be_error }
    end

    context 'when result is an "ok" type' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, attributes: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect(result).not_to be_error }
    end

    context 'when result is an "error" type' do
      subject(:result) { described_class::Error.new(duration_ext_ns: 0, input_truncated: false) }

      it { expect(result).to be_error }
    end
  end

  describe "#keep?" do
    context 'when result is a "match" type' do
      subject(:result) do
        described_class::Match.new(
          events: [], actions: {}, attributes: {}, timeout: false, keep: true, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect(result).to be_keep }
    end

    context 'when result is an "ok" type' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, attributes: {}, timeout: false, keep: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false,
        )
      end

      it { expect(result).not_to be_keep }
    end

    context 'when result is an "error" type' do
      subject(:result) { described_class::Error.new(duration_ext_ns: 0, input_truncated: false) }

      it { expect(result).not_to be_keep }
    end
  end
end
