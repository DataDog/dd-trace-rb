# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/anonimyzer'

RSpec.describe Datadog::AppSec::Anonimyzer do
  describe '.anonimyze' do
    it { expect(described_class.anonimyze(1)).to eq('anon_6b86b273ff34fce19d6b804eff5a3f57') }
    it { expect(described_class.anonimyze(true)).to eq('anon_b5bea41b6c623f7c09f1bf24dcae58eb') }
    it { expect(described_class.anonimyze(Class.new)).to eq('anon_1e43d708d963dbd57cf533ab4f7658f8') }
    it { expect(described_class.anonimyze('Hello world')).to eq('anon_64ec88ca00b268e5ba1a35678a1b5316') }
  end
end
