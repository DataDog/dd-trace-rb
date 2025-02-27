# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Anonymizer do
  describe '.anonymize' do
    it { expect(described_class.anonymize('1')).to eq('anon_6b86b273ff34fce19d6b804eff5a3f57') }
    it { expect(described_class.anonymize('true')).to eq('anon_b5bea41b6c623f7c09f1bf24dcae58eb') }
    it { expect(described_class.anonymize('nil')).to eq('anon_5da3a4c7f117944275b4c8629c491640') }
    it { expect(described_class.anonymize('Hello world')).to eq('anon_64ec88ca00b268e5ba1a35678a1b5316') }
    it { expect { described_class.anonymize(1) }.to raise_error(ArgumentError) }
  end
end
