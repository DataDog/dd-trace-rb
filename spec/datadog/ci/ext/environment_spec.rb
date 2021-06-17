require 'datadog/ci/spec_helper'

require 'json'
require 'datadog/ci/ext/environment'

RSpec.describe Datadog::CI::Ext::Environment do
  describe '.tags' do
    subject(:tags) { described_class.tags(env) }
    let(:env) { {} }

    Dir.glob("#{File.dirname(__FILE__)}/fixtures/ci/*.json") do |filename|
      File.open(filename) do |f|
        context "for fixture #{File.basename(filename)}" do
          JSON.parse(f.read).each_with_index do |(env, tags), i|
            context "##{i}" do
              let(:env) { env }

              it 'matches tags' do
                ClimateControl.modify('HOME' => env['HOME']) do
                  is_expected.to eq(tags)
                end
              end
            end
          end
        end
      end
    end
  end
end
