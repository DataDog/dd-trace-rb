require 'datadog/tracing/contrib/support/spec_helper'

require 'active_record'
require 'datadog/tracing/contrib/active_record/configuration/resolver'

RSpec.describe Datadog::Tracing::Contrib::ActiveRecord::Configuration::Resolver do
  subject(:resolver) { described_class.new(configuration) }

  let(:configuration) { nil }

  describe '#add' do
    subject(:add) { resolver.add(matcher, config) }

    let(:matcher) { instance_double('matcher') }
    let(:config) { instance_double('config') }

    context 'with a hash matcher' do
      let(:matcher) do
        {
          adapter: 'adapter',
          host: 'host',
          port: 123,
          username: nil,
          unrelated_setting: 'foo'
        }
      end

      it 'resolves to a normalized hash matcher' do
        add

        expect(resolver.configurations)
          .to eq(
            {
              adapter: 'adapter',
              host: 'host',
              port: 123
            } => config
          )
      end
    end

    context 'with a symbol matcher' do
      let(:matcher) { :test }

      context 'with a valid ActiveRecord database' do
        let(:configuration) { { 'test' => db_config } }

        let(:db_config) do
          {
            adapter: 'adapter',
            host: 'host',
            port: 123
          }
        end

        it 'resolves to a normalized hash matcher' do
          add

          expect(resolver.configurations).to include(db_config => config)
        end
      end

      context 'without a valid ActiveRecord database' do
        it "logs error and doesn't register matcher" do
          expect(Datadog.logger).to receive(:error).with(/:test/)

          add

          expect(resolver.configurations).to be_empty
        end
      end
    end

    context 'with a URL matcher' do
      let(:matcher) { 'adapter://host:123' }

      let(:db_config) do
        {
          adapter: 'adapter',
          host: 'host',
          port: 123
        }
      end

      it 'resolves to a normalized hash matcher' do
        add

        expect(resolver.configurations).to include(db_config => config)
      end
    end
  end

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(actual) }

    let(:matchers) do
      [matcher]
    end
    let(:actual) do
      {
        adapter: 'adapter',
        host: 'host',
        port: 123,
        database: 'database',
        username: 'username'
      }
    end
    let(:match_all) { {} }

    before do
      matchers.each do |m|
        resolver.add(m, m)
      end
    end

    shared_examples 'a matching pattern' do
      it 'matches the pattern' do
        is_expected.to be(matcher)

        unless matcher == match_all
          expect(resolver.resolve({ host: Object.new }))
            .to be_nil,
              "Expected pattern to match only the input, but it's matching everything. "\
                                      'Unless you explicitly wanted to match all patterns, this is unlikely to be desired.'
        end
      end
    end

    context 'with exact match' do
      let(:matcher) do
        {
          adapter: 'adapter',
          host: 'host',
          port: 123,
          database: 'database',
          username: 'username'
        }
      end

      it_behaves_like 'a matching pattern'
    end

    context 'with an empty matcher' do
      let(:matcher) { match_all }

      it_behaves_like 'a matching pattern'
    end

    context 'with partial match' do
      context 'that matches' do
        let(:matcher) do
          {
            adapter: 'adapter'
          }
        end

        it_behaves_like 'a matching pattern'
      end

      context 'that does not match' do
        let(:matcher) do
          {
            adapter: 'not matching'
          }
        end

        it { is_expected.to be_nil }
      end

      context 'with a makara connection' do
        let(:actual) do
          {
            name: 'master/1'
          }
        end

        let(:matcher) do
          {
            makara_role: 'master'
          }
        end

        it_behaves_like 'a matching pattern'

        context 'with a name not respecting the makara role pattern' do
          let(:actual) do
            {
              name: 'a14%_ #9(]'
            }
          end

          let(:matcher) do
            {
              makara_role: 'a14%_ #9(]'
            }
          end

          it_behaves_like 'a matching pattern'
        end
      end
    end

    context 'with multiple matchers' do
      let(:matchers) { [first_matcher, second_matcher] }

      context 'that do not match' do
        let(:first_matcher) do
          {
            port: 0
          }
        end

        let(:second_matcher) do
          {
            adapter: 'not matching'
          }
        end

        it { is_expected.to be_nil }
      end

      context 'when the first one matches' do
        let(:first_matcher) do
          {
            database: 'database'
          }
        end

        let(:second_matcher) do
          {
            database: 'not correct'
          }
        end

        it_behaves_like 'a matching pattern' do
          let(:matcher) { first_matcher }
        end
      end

      context 'when the second one matches' do
        let(:first_matcher) do
          {
            database: 'not right'
          }
        end

        let(:second_matcher) do
          {
            database: 'database'
          }
        end

        it_behaves_like 'a matching pattern' do
          let(:matcher) { second_matcher }
        end
      end

      context 'when all match' do
        context 'and are the same matcher' do
          let(:first_matcher) do
            {
              host: 'host'
            }
          end

          let(:second_matcher) do
            {
              host: 'host'
            }
          end

          it 'replaces the first with the second matcher' do
            is_expected.to be(second_matcher)
          end
        end

        context 'and are not same matcher' do
          let(:first_matcher) do
            {
              host: 'host'
            }
          end

          let(:second_matcher) { match_all }

          it 'matches the latest added matcher' do
            is_expected.to be(second_matcher)
          end
        end
      end
    end
  end
end
