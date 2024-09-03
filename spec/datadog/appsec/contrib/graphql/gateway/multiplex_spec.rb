# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/graphql/gateway/multiplex'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex do
  subject(:dd_multiplex) do
    described_class.new(multiplex)
  end

  let(:schema) do
    stub_const('TestSchema', Class.new(::GraphQL::Schema))
  end

  let(:multiplex) do
    ::GraphQL::Execution::Multiplex.new(
      schema: schema,
      queries: queries,
      context: { :dataloader => GraphQL::Dataloader.new(nonblocking: nil) },
      max_complexity: nil
    )
  end

  describe '#arguments' do
    let(:query) do
      ::GraphQL::Query.new(
        schema,
        <<~END_OF_QUERY,
          fragment AuthorData on Author {
            name
            username
          }

          fragment CommentData on Comment {
            author {
              ...AuthorData
            }
            content
          }

          query MyTestQuery (
            $postSlug: String = "my-first-post",
            $ignoreDislikes: Boolean!,
            $withComments: Boolean!,
            $skipRating: Boolean!
          ) {
            firstPost: post(slug: $postSlug) {
              title
              slug
              content
              rating(ignoreDislikes: $ignoreDislikes) @skip(if: $skipRating)
              author {
                ...AuthorData
              }
              comments @include(if: $withComments) {
                ...CommentData
                comments {
                  ...CommentData
                }
              }
            }
            secondPost: post(slug: "another-post") {
              title
              slug
            }
            author(username: "john") {
              ...AuthorData
            }
          }
        END_OF_QUERY
        variables: query_variables
      )
    end

    let(:mutation) do
      ::GraphQL::Query.new(
        schema,
        <<~END_OF_QUERY,
          mutation addPost(
            $postContent: String!,
            $authorID: String!
          ) {
            addPost(
              input: {
                title: "My second post",
                content: $postContent,
                authorId: $authorID
              }
            ) {
              post {
                title
                slug
                content
              }
            }
          }
        END_OF_QUERY
        variables: mutation_variables
      )
    end

    let(:subscription) do
      ::GraphQL::Query.new(
        schema,
        <<~END_OF_QUERY,
          subscription postComments($postSlug: String!) {
            postCommentsSubscribe(slug: $postSlug) {
              comments {
                author { name }
                content
              }
            }
          }
        END_OF_QUERY
        variables: subscription_variables
      )
    end

    let(:queries) { [query, mutation, subscription] }

    context 'when all variables are provided' do
      let(:query_variables) do
        {
          postSlug: 'some-post',
          ignoreDislikes: true,
          withComments: true,
          skipRating: false
        }
      end

      let(:mutation_variables) do
        {
          postContent: 'Some content',
          authorID: '123'
        }
      end

      let(:subscription_variables) do
        {
          postSlug: 'one-more-post'
        }
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to eq(
          'firstPost' => [{ 'slug' => 'some-post' }],
          'secondPost' => [{ 'slug' => 'another-post' }],
          'author' => [{ 'username' => 'john' }],
          'comments' => [{ 'include' => { 'if' => true } }],
          'rating' => [{ 'ignoreDislikes' => true, 'skip' => { 'if' => false } }],
          'addPost' => [{
            'input' => {
              'title' => 'My second post',
              'content' => 'Some content',
              'authorId' => '123'
            }
          }],
          'postCommentsSubscribe' => [{ 'slug' => 'one-more-post' }]
        )
      end
    end

    context 'when variables with default value are not provided' do
      let(:queries) { [query] }

      let(:query_variables) do
        {
          ignoreDislikes: true,
          withComments: true,
          skipRating: false
        }
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to eq(
          'firstPost' => [{ 'slug' => 'my-first-post' }],
          'secondPost' => [{ 'slug' => 'another-post' }],
          'author' => [{ 'username' => 'john' }],
          'comments' => [{ 'include' => { 'if' => true } }],
          'rating' => [{ 'ignoreDislikes' => true, 'skip' => { 'if' => false } }]
        )
      end
    end
  end

  describe '#queries' do
    let(:query) do
      ::GraphQL::Query.new(
        schema,
        <<~END_OF_QUERY,
          query getPost($postSlug: String!) {
            post(slug: $postSlug) { title }
          }
        END_OF_QUERY
      )
    end

    let(:queries) { [query] }

    it 'returns queries' do
      expect(dd_multiplex.queries).to eq(queries)
    end
  end
end
