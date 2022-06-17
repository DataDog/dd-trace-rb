require 'spec_helper'

RSpec.shared_examples 'an optional string parameter' do |argument|
  context 'when argument is nil' do
    let(argument.to_sym) { nil }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when argument is valid' do
    let(argument.to_sym) { 'valid string' }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'a required string parameter' do |argument|
  context 'when argument is nil' do
    let(argument.to_sym) { nil }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when argument is valid' do
    let(argument.to_sym) { 'valid string' }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'a required boolean parameter' do |argument|
  context 'when argument is nil' do
    let(argument.to_sym) { nil }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when argument is true' do
    let(argument.to_sym) { true }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when argument is false' do
    let(argument.to_sym) { false }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'an optional boolean parameter' do |argument|
  context 'when argument is nil' do
    let(argument.to_sym) { nil }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when argument is true' do
    let(argument.to_sym) { true }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when argument is false' do
    let(argument.to_sym) { false }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end
