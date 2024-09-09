# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/graphql/gateway/multiplex'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex do
  subject(:dd_multiplex) { described_class.new(multiplex) }

  let(:schema) do
    # we are only testing how arguments are extracted from the queries,
    # therefore we don't need a real schema here
    stub_const('TestSchema', Class.new(::GraphQL::Schema))
  end

  let(:multiplex) do
    ::GraphQL::Execution::Multiplex.new(
      schema: schema,
      queries: queries,
      context: { dataloader: GraphQL::Dataloader.new(nonblocking: nil) },
      max_complexity: nil
    )
  end

  describe '#arguments' do
    context 'query with argument values provided inline in the query' do
      let(:queries) do
        [
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY
              query {
                post(slug: "my-first-post") {
                  title
                  content
                }
                author(username: "john") { name }
              }
            END_OF_QUERY
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'post' => [{ 'slug' => 'my-first-post' }],
            'author' => [{ 'username' => 'john' }]
          )
        )
      end
    end

    context 'query with argument values provided in query variables' do
      let(:queries) do
        [
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              query getPost(
                $postSlug: String = "default-post",
                $authorUsername: String!
              ) {
                post(slug: $postSlug) {
                  title
                  content
                }
                author(username: $authorUsername) { name }
              }
            END_OF_QUERY
            variables: { 'postSlug' => 'some-post', 'authorUsername' => 'jane' }
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'post' => [{ 'slug' => 'some-post' }],
            'author' => [{ 'username' => 'jane' }]
          )
        )
      end
    end

    context 'query with arguments with a default value and no value provided' do
      let(:queries) do
        [
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY
              query getPost($postSlug: String = "default-post") {
                post(slug: $postSlug) {
                  title
                  content
                }
              }
            END_OF_QUERY
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to eq('post' => [{ 'slug' => 'default-post' }])
      end
    end

    context 'multiple queries that are querying the same field' do
      let(:queries) do
        [
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              query getPost($postSlug: String) {
                post(slug: $postSlug) {
                  title
                  content
                }
              }
            END_OF_QUERY
            variables: { 'postSlug' => 'some-post' }
          ),
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              query getPost($postSlug: String) {
                post(slug: $postSlug) {
                  title
                  content
                }
              }
            END_OF_QUERY
            variables: { 'postSlug' => 'another-post' }
          )
        ]
      end

      it 'returns all arguments for the field' do
        expect(dd_multiplex.arguments).to(
          eq('post' => [{ 'slug' => 'some-post' }, { 'slug' => 'another-post' }])
        )
      end
    end

    context 'query with aliases' do
      let(:queries) do
        [
          GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              query MyTestQuery ($firstPostSlug: String, $secondPostSlug: String) {
                firstPost: post(slug: $firstPostSlug) { title }
                secondPost: post(slug: $secondPostSlug) { title }
              }
            END_OF_QUERY
            variables: {
              'firstPostSlug' => 'first-post',
              'secondPostSlug' => 'second-post'
            }
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'firstPost' => [{ 'slug' => 'first-post' }],
            'secondPost' => [{ 'slug' => 'second-post' }]
          )
        )
      end
    end

    context 'query with arguments to non-resolver fields' do
      let(:queries) do
        [
          GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              query MyTestQuery ($postSlug: String!, $ignoreDislikes: Boolean!) {
                post(slug: $postSlug) {
                  title
                  rating(ignoreDislikes: $ignoreDislikes)
                }
              }
            END_OF_QUERY
            variables: {
              'postSlug' => 'some-post',
              'ignoreDislikes' => true
            }
          )
        ]
      end

      it 'returns correct arguments including non-resolver field arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'post' => [{ 'slug' => 'some-post' }],
            'rating' => [{ 'ignoreDislikes' => true }]
          )
        )
      end
    end

    context 'query with directives' do
      let(:queries) do
        [
          GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              fragment AuthorData on Author {
                name
                username
              }

              query MyTestQuery (
                $postSlug: String!,
                $withComments: Boolean!,
                $skipAuthor: Boolean!
              ) {
                post(slug: $postSlug) {
                  title
                  content
                  author @skip(if: $skipAuthor) {
                    ...AuthorData
                  }
                  comments @include(if: $withComments) {
                    author { ...AuthorData }
                    content
                  }
                }
              }
            END_OF_QUERY
            variables: { postSlug: 'some-post', withComments: true, skipAuthor: false }
          )
        ]
      end

      it 'returns correct arguments with directive arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'post' => [{ 'slug' => 'some-post' }],
            'author' => [{ 'skip' => { 'if' => false } }],
            'comments' => [{ 'include' => { 'if' => true } }]
          )
        )
      end
    end

    # this spec is to ensure that no exceptions are raised when query contains fragments
    context 'query with fragments' do
      let(:queries) do
        [
          GraphQL::Query.new(
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

              query MyTestQuery ($postSlug: String = "my-first-post") {
                post(slug: $postSlug) {
                  title
                  content
                  author {
                    ...AuthorData
                  }
                  comments {
                    ...CommentData
                  }
                }
              }
            END_OF_QUERY
            variables: { 'postSlug' => 'some-post' }
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to eq('post' => [{ 'slug' => 'some-post' }])
      end
    end

    context 'mutation' do
      let(:queries) do
        [
          ::GraphQL::Query.new(
            schema,
            <<~END_OF_QUERY,
              mutation addPost(
                $postContent: String!,
                $authorID: String!
              ) {
                addPost(
                  input: {
                    title: "Some title",
                    content: $postContent,
                    authorId: $authorID
                  }
                ) {
                  post { title slug content }
                }
              }
            END_OF_QUERY
            variables: { 'postContent' => 'Some content', 'authorID' => '1' }
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to(
          eq(
            'addPost' => [
              {
                'input' => {
                  'content' => 'Some content',
                  'authorId' => '1',
                  'title' => 'Some title'
                }
              }
            ]
          )
        )
      end
    end

    context 'subscription' do
      let(:queries) do
        [
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
            variables: { 'postSlug' => 'some-post' }
          )
        ]
      end

      it 'returns correct arguments' do
        expect(dd_multiplex.arguments).to(
          eq('postCommentsSubscribe' => [{ 'slug' => 'some-post' }])
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
