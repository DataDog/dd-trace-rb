require 'spec_helper'

require 'ddtrace/quantization/http'

RSpec.describe Datadog::Quantization::HTTP do
  describe '#url' do
    subject(:result) { described_class.url(url, options) }

    let(:options) { {} }

    context 'given a URL' do
      let(:url) { 'http://example.com/path?category_id=1&sort_by=asc#featured' }

      context 'default behavior' do
        it { is_expected.to eq('http://example.com/path?category_id&sort_by') }
      end

      context 'default behavior for an array' do
        let(:url) { 'http://example.com/path?categories[]=1&categories[]=2' }

        it { is_expected.to eq('http://example.com/path?categories[]') }
      end

      context 'with query: show: value' do
        let(:options) { { query: { show: ['category_id'] } } }

        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by') }
      end

      context 'with query: show: :all' do
        let(:options) { { query: { show: :all } } }

        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by=asc') }
      end

      context 'with query: exclude: value' do
        let(:options) { { query: { exclude: ['sort_by'] } } }

        it { is_expected.to eq('http://example.com/path?category_id') }
      end

      context 'with query: exclude: :all' do
        let(:options) { { query: { exclude: :all } } }

        it { is_expected.to eq('http://example.com/path') }
      end

      context 'with show: :all' do
        let(:options) { { fragment: :show } }

        it { is_expected.to eq('http://example.com/path?category_id&sort_by#featured') }
      end

      context 'with Unicode characters' do
        # URLs do not permit unencoded non-ASCII characters in the URL.
        let(:url) { 'http://example.com/path?繋がってて' }

        it { is_expected.to eq(described_class::PLACEHOLDER) }
      end
    end
  end

  describe '#query' do
    subject(:result) { described_class.query(query, options) }

    context 'given a query' do
      context 'and no options' do
        let(:options) { {} }

        context 'with a single parameter' do
          let(:query) { 'foo=foo' }

          it { is_expected.to eq('foo') }

          context 'with an invalid byte sequence' do
            # \255 is off-limits https://en.wikipedia.org/wiki/UTF-8#Codepage_layout
            # There isn't a graceful way to handle this without stripping interesting
            # characters out either; so just raise an error and default to the placeholder.
            let(:query) { "foo\255=foo" }

            it { is_expected.to eq('?') }
          end
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }

          it { is_expected.to eq('foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }

          it { is_expected.to eq('foo[]') }
        end

        context 'with semi-colon style parameters' do
          let(:query) { 'foo;bar' }
          # Notice semicolons aren't preseved... no great way of handling this.
          # Semicolons are illegal as of 2014... so this is an edge case.
          # See https://www.w3.org/TR/2014/REC-html5-20141028/forms.html#url-encoded-form-data

          it { is_expected.to eq('foo;bar') }
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }

          it { is_expected.to eq('user[id]&user[name]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }

            it { is_expected.to eq('users[][id]&users[][name]') }
          end
        end
      end

      context 'and a show: :all option' do
        let(:query) { 'foo=foo&bar=bar' }
        let(:options) { { show: :all } }

        it { is_expected.to eq(query) }
      end

      context 'and a show option' do
        context 'with a single parameter' do
          let(:query) { 'foo=foo' }
          let(:key) { 'foo' }
          let(:options) { { show: [key] } }

          it { is_expected.to eq('foo=foo') }

          context 'that has a Unicode key' do
            let(:query) { '繋=foo' }
            let(:key) { '繋' }

            it { is_expected.to eq('繋=foo') }

            context 'that is encoded' do
              let(:query) { '%E7%B9%8B=foo' }
              let(:key) { '%E7%B9%8B' }

              it { is_expected.to eq('%E7%B9%8B=foo') }
            end
          end

          context 'that has a Unicode value' do
            let(:query) { 'foo=繋' }
            let(:key) { 'foo' }

            it { is_expected.to eq('foo=繋') }

            context 'that is encoded' do
              let(:query) { 'foo=%E7%B9%8B' }

              it { is_expected.to eq('foo=%E7%B9%8B') }
            end
          end

          context 'that has a Unicode key and value' do
            let(:query) { '繋=繋' }
            let(:key) { '繋' }

            it { is_expected.to eq('繋=繋') }

            context 'that is encoded' do
              let(:query) { '%E7%B9%8B=%E7%B9%8B' }
              let(:key) { '%E7%B9%8B' }

              it { is_expected.to eq('%E7%B9%8B=%E7%B9%8B') }
            end
          end
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }
          let(:options) { { show: ['foo'] } }

          it { is_expected.to eq('foo=foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { show: ['foo[]'] } }

          it { is_expected.to eq('foo[]=bar&foo[]=baz') }

          context 'that contains encoded braces' do
            let(:query) { 'foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D' }

            it { is_expected.to eq('foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D') }

            context 'that exactly matches the key' do
              let(:query) { 'foo[]=foo%5B%5D&foo[]=foo%5B%5D' }

              it { is_expected.to eq('foo[]=foo%5B%5D&foo[]=foo%5B%5D') }
            end
          end
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { show: ['user[id]'] } }

          it { is_expected.to eq('user[id]=1&user[name]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { show: ['users[][id]'] } }

            it { is_expected.to eq('users[][id]=1&users[][name]&users[][id]=2') }
          end
        end
      end

      context 'and an exclude: :all option' do
        let(:query) { 'foo=foo&bar=bar' }
        let(:options) { { exclude: :all } }

        it { is_expected.to eq('') }
      end

      context 'and an exclude option' do
        context 'with a single parameter' do
          let(:query) { 'foo=foo' }
          let(:options) { { exclude: ['foo'] } }

          it { is_expected.to eq('') }
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }
          let(:options) { { exclude: ['foo'] } }

          it { is_expected.to eq('bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { exclude: ['foo[]'] } }

          it { is_expected.to eq('') }
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { exclude: ['user[name]'] } }

          it { is_expected.to eq('user[id]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { exclude: ['users[][name]'] } }

            it { is_expected.to eq('users[][id]') }
          end
        end
      end
    end
  end
end
