# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Config

# Normalises site and template pagination config into predictable internal structures consumed by pagination runtime classes.
#
# Site-level config is normalised to the nested public v3 structure:
# - pagination.syntax.*
# - pagination.templates.collection
# - pagination.templates.location
# - pagination.templates.generate
# - pagination.templates.*
#
# Template-level config is normalised to a flat hash used during
# pagination emission for one concrete template page/document.
class Normaliser
	
	LEGACY_FILTER_KEYS = %w[category tag locale].freeze
	LEGACY_TEMPLATE_DEFAULT_KEYS = %w[items collection filters sort per_page limit offset trail title permalink sort_field sort_reverse indexpage extension].freeze
	LEGACY_SITE_KEY_ALIASES = %w[split separator nested_key_separator].freeze
	V2_AUTOPAGE_DEFAULTS = {
		'tags' => {
			'layout' => 'autopage_tags.html',
			'title' => 'Posts tagged with :tag',
			'permalink' => '/tag/:tag',
			'slugify' => {
				'mode' => 'default',
				'case' => false
			}
		},
		'categories' => {
			'layout' => 'autopage_category.html',
			'title' => 'Posts in category :cat',
			'permalink' => '/category/:cat',
			'slugify' => {
				'mode' => 'default',
				'case' => false
			}
		},
		'collections' => {
			'layout' => 'autopage_collection.html',
			'title' => 'Posts in collection :coll',
			'permalink' => '/collection/:coll/',
			'slugify' => {
				'mode' => 'default',
				'case' => false
			}
		}
	}.freeze

	# Produces canonical site-level pagination config.
	#
	# Merge order:
	# defaults -> compatibility profile -> legacy overlays -> user config.
	def self.normalise_site_config(site_config)
		site_hash = Utils.safe_hash(site_config)
		raw_pagination = normalise_site_pagination_source(site_hash['pagination'])

		compatibility_mode = normalise_compatibility(raw_pagination['compatibility'])

		config = Utils.deep_copy(DEFAULTS)
		if compatibility_mode && COMPATIBILITY_PROFILES.key?(compatibility_mode)
			config = Jekyll::Utils.deep_merge_hashes(config, Utils.deep_copy(COMPATIBILITY_PROFILES[compatibility_mode]))
		end

		if compatibility_mode == 'v1'
			config = Jekyll::Utils.deep_merge_hashes(config, legacy_v1_overlay(site_hash))
		end

		config = Jekyll::Utils.deep_merge_hashes(config, raw_pagination)
		config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

		normalise_site_common!(config, compatibility_mode, raw_pagination)
		migrate_legacy_shortcuts!(config['templates'], compatibility_mode, raw_pagination)
		apply_v2_legacy_page_templates!(config['templates'], raw_pagination, compatibility_mode)
		migrate_v2_autopages!(config, site_hash['autopages'], compatibility_mode)

		config
	end

	# Produces template-level pagination config used while paginating one
	# template page/document.
	#
	# The output is intentionally flat so downstream pipeline code can read
	# values directly without re-resolving site defaults.
	def self.normalise_template_config(site_config, template_pagination_config)
		raw_template_pagination = Utils.safe_hash(template_pagination_config)
		compatibility_mode = normalise_compatibility(raw_template_pagination['compatibility']) || normalise_compatibility(site_config['compatibility'])
		site_template_defaults = extract_template_defaults_overrides('templates' => site_config['templates'])

		page_config = Jekyll::Utils.deep_merge_hashes(
			Utils.deep_copy(site_template_defaults),
			raw_template_pagination
		)

		page_config['enabled'] = if raw_template_pagination.key?('enabled')
																!!raw_template_pagination['enabled']
															else
																!!site_config['enabled']
															end
		page_config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

		syntax = resolve_template_syntax(raw_template_pagination, site_config['syntax'])
		page_config['split'] = syntax['split']
		page_config['separator'] = syntax['separator']

		page_config = normalise_template_defaults(
			page_config,
			raw_overrides: raw_template_pagination,
			split_delimiter: syntax['split'],
			keywords: site_config['keywords']
		)

		migrate_legacy_shortcuts!(page_config, compatibility_mode, raw_template_pagination)
		apply_v2_legacy_page_templates!(page_config, raw_template_pagination, compatibility_mode)

		page_config
	end
end

end
end
end
end
