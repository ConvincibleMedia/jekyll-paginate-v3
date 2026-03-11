# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

# Default configuration for jekyll-paginate-v3.
#
# These defaults intentionally describe the new v3 behaviour. Legacy
# v1/v2 behaviour is layered on top through compatibility profiles.
module Config
	KEYWORD_DEFAULTS = {
		'pages' => 'pages',
		'all' => 'all',
		'everything' => 'everything',
		'self' => 'self',
		'shadow' => 'shadow',
		'clone' => 'clone',
		'now' => 'now',
		'today' => 'today',
		'day' => 'day',
		'month' => 'month',
		'year' => 'year',
		'hour' => 'hour',
		'minute' => 'minute',
		'second' => 'second',
		'items' => 'items'
	}.freeze

	DEFAULTS = {
		'enabled' => true,
		'compatibility' => nil,
		'debug' => false,
		'syntax' => {
			'separator' => '.',
			'split' => ','
		},
		'keywords' => {},
		'equivalents' => [
			['tag', 'tags'],
			['category', 'categories']
		],
		'items' => 'posts',
		'collection' => ['self', 'shadow'],
		'filters' => [],
		'sort' => 'date desc',
		'per_page' => 10,
		'limit' => 0,
		'offset' => 0,
		'trail' => {
			'before' => 2,
			'after' => 2
		},
		'title' => ':title - page :num',
		'permalink' => '/page/:num',
		'layout' => nil,
		'layouts' => [],
		'group' => [],
		'slugify' => {
			'mode' => 'default',
			'lowercase' => true
		},
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
			'syntax' => {
				'separator' => ':'
			},
			'keywords' => {
				'all' => 'collections',
				'items' => 'posts'
			},
			'permalink' => '/page/:num/',
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
