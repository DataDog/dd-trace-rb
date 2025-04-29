# frozen_string_literal: true

RSpec.shared_examples_for 'a binary setting with' do |env_variable:, default:|
  context "when environment variable `#{env_variable}`" do
    around { |example| ClimateControl.modify(env_variable => environment) { example.run } }

    context 'is not defined' do
      let(:environment) { nil }

      it { is_expected.to be default }
    end

    [true, false].each do |value|
      context "is defined as #{value}" do
        let(:environment) { value.to_s }

        it { is_expected.to be value }
      end
    end
  end
end
