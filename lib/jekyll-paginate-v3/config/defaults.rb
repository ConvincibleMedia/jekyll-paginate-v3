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

	# Internal collection-mode identifiers. These never appear in user
	# configuration, which lets a renamed keyword release its original word for
	# use as a real Jekyll collection label.
	COLLECTION_TARGET_PAGES = '__paginate_v3_collection_target_pages__'.freeze
	COLLECTION_TARGET_SELF = '__paginate_v3_collection_target_self__'.freeze
	COLLECTION_TARGET_SHADOW = '__paginate_v3_collection_target_shadow__'.freeze
	COLLECTION_TARGET_CLONE = '__paginate_v3_collection_target_clone__'.freeze
	COLLECTION_TARGET_BY_KEY = {
		'pages' => COLLECTION_TARGET_PAGES,
		'self' => COLLECTION_TARGET_SELF,
		'shadow' => COLLECTION_TARGET_SHADOW,
		'clone' => COLLECTION_TARGET_CLONE
	}.freeze

	# Slugification modes exposed by pagination config. Every supported mode
	# must produce a route key rather than bypassing character filtering.
	SLUGIFY_MODES = %w[default ascii latin].freeze

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
		'items' => nil,
		'collection' => [COLLECTION_TARGET_SELF, COLLECTION_TARGET_SHADOW],
		'filters' => nil,
		'sort' => 'date desc',
		'per_page' => 10,
		'limit' => 0,
		'offset' => 0,
		'trail' => 5,
		'title' => '{{ title }} - {{ num }}',
		'permalink' => '{{ num }}',
		'layout' => nil,
		'layouts' => [],
		'group' => nil,
		'slugify' => {
			'mode' => 'default',
			'lowercase' => true
		},
		'templates' => {
			'location' => nil,
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
			'items' => 'posts',
			'title' => ':title - page :num',
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
				'generate' => []
			}
		}
	}.freeze
end

end
end
end
