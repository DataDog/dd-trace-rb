# typed: ignore

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'

RSpec.describe Datadog::AppSec::Processor do
  before do
    skip 'disabled for Java' if RUBY_PLATFORM.include?('java')

    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug?).and_return true
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    allow(Datadog).to receive(:logger).and_return(logger)
  end

  context 'self' do
    it 'detects if the WAF is unavailable' do
      hide_const('Datadog::AppSec::WAF')

      expect(described_class.libddwaf_required?).to be false
    end

    it 'detects if the WAF is available' do
      stub_const('Datadog::AppSec::WAF', Module.new)

      expect(described_class.libddwaf_required?).to be true
    end

    it 'reports via return of libddwaf loading failure' do
      allow(Object).to receive(:require).with('libddwaf').and_raise(LoadError)

      expect(described_class.require_libddwaf).to be false
    end

    it 'reports via return of libddwaf loading success (first require)' do
      allow(Object).to receive(:require).with('libddwaf').and_return(true)

      expect(described_class.require_libddwaf).to be true
    end

    it 'reports via return of libddwaf loading success (second require)' do
      allow(Object).to receive(:require).with('libddwaf').and_return(false)

      expect(described_class.require_libddwaf).to be true
    end
  end

  describe '#load_libddwaf' do
    context 'when LoadError is raised' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_raise(LoadError)
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be false }
    end

    context 'when loaded but missing mandatory const' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        hide_const('Datadog::AppSec::WAF')
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be false }
    end

    context 'when loaded successfully' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        stub_const('Datadog::AppSec::WAF', Module.new)
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be true }
    end
  end

  describe '#load_ruleset' do
    before do
      allow(Datadog::AppSec.settings).to receive(:ruleset).and_return(ruleset)
    end

    let(:basic_ruleset) do
      {
        'version' => '1.0',
        'events' => [
          {
            'id' => 1,
            'name' => 'Rule 1',
            'tags' => { 'type' => 'flow1' },
            'conditions' => [
              { 'operation' => 'match_regex', 'parameters' => { 'inputs' => ['value2'], 'regex' => 'rule1' } },
            ],
            'action' => 'record',
          }
        ]
      }
    end

    context 'when ruleset is default' do
      let(:ruleset) { :recommended }

      it { expect(described_class.new.send(:load_ruleset)).to be true }
    end

    context 'when ruleset is an existing path' do
      let(:ruleset) { "#{__dir__}/../../../lib/datadog/appsec/assets/waf_rules/recommended.json" }

      it { expect(described_class.new.send(:load_ruleset)).to be true }
    end

    context 'when ruleset is a non existing path' do
      let(:ruleset) { '/does/not/exist' }

      it { expect(described_class.new.send(:load_ruleset)).to be false }
    end

    context 'when ruleset is IO-like' do
      let(:ruleset) { StringIO.new(JSON.dump(basic_ruleset)) }

      it { expect(described_class.new.send(:load_ruleset)).to be true }
    end

    context 'when ruleset is Ruby' do
      let(:ruleset) { basic_ruleset }

      it { expect(described_class.new.send(:load_ruleset)).to be true }
    end

    context 'when ruleset is not parseable' do
      let(:ruleset) { StringIO.new('this is not json') }

      it { expect(described_class.new.send(:load_ruleset)).to be false }
    end
  end

  describe '#create_waf_handle' do
    let(:ruleset) { :recommended }

    before do
      allow(Datadog::AppSec.settings).to receive(:ruleset).and_return(ruleset)
    end

    context 'when ruleset is default' do
      let(:ruleset) { :recommended }

      it { expect(described_class.new.send(:create_waf_handle)).to be true }
    end

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      it { expect(described_class.new.send(:create_waf_handle)).to be false }
    end
  end

  describe '#initialize' do
    let(:ruleset) { :recommended }

    subject(:processor) { described_class.new }

    before do
      allow(Datadog::AppSec.settings).to receive(:ruleset).and_return(ruleset)
    end

    context 'when libddwaf fails to load' do
      before do
        expect(described_class).to receive(:require_libddwaf).and_return(false)

        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when libddwaf fails to provide WAF' do
      before do
        expect(described_class).to receive(:require_libddwaf).and_return(true)
        expect(described_class).to receive(:libddwaf_required?).and_return(false)

        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is a non existing path' do
      let(:ruleset) { '/does/not/exist' }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is not parseable' do
      let(:ruleset) { StringIO.new('this is not json') }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when things are OK' do
      before do
        expect(Datadog.logger).to_not receive(:warn)
      end

      it { is_expected.to be_ready }
    end
  end
end
