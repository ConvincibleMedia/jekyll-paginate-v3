# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Config
        # Default configuration for jekyll-paginate-v3.
        #
        # These defaults intentionally describe the new v3 behaviour. Legacy
        # v1/v2 behaviour is layered on top through compatibility profiles.
        DEFAULTS = {
          'enabled' => false,
          'compatibility' => nil,
          'split' => ',',
          'nested_key_separator' => '.',
          'keywords' => {
            'pages' => 'pages',
            'all' => 'all',
            'everything' => 'everything',
            'now' => 'now',
            'items' => 'items'
          },
          'equivalents' => [
            ['tag', 'tags'],
            ['category', 'categories']
          ],
          'items' => 'posts',
          'filters' => {},
          'offset' => 0,
          'per_page' => 10,
          'permalink' => '/page/:num/',
          'title' => ':title - page :num',
          'sort' => ['date desc'],
          'limit' => 0,
          'trail' => {
            'before' => 2,
            'after' => 2
          },
          'indexpage' => 'index',
          'extension' => 'html',
          'debug' => false,
          'templates' => {
            'location' => 'pages',
            'generate' => []
          }
        }.freeze

        # Compatibility overlays merged after DEFAULTS but before user config.
        #
        # v2 keeps historical public contract where the paginator payload key is
        # `posts` and where legacy shorthand keys are accepted and up-migrated.
        #
        # v1 keeps legacy config keys working while staying on the shared v3
        # pagination pipeline.
        COMPATIBILITY_PROFILES = {
          'v2' => {
            'enabled' => true,
            'nested_key_separator' => ':',
            'keywords' => {
              'all' => 'collections',
              'items' => 'posts'
            },
            'trail' => {
              'before' => 2,
              'after' => 2
            }
          },
          'v1' => {
            'enabled' => true,
            'keywords' => {
              'items' => 'posts'
            },
            'items' => 'posts',
            'templates' => {
              'location' => 'pages',
              'generate' => []
            }
          }
        }.freeze
      end
    end
  end
end
