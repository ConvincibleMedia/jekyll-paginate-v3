# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Config
class Normaliser
	class << self
		# Site and template config normalisation helpers used by `Normaliser`.
		# Structure: site-level keys are canonicalised first, then template
		# defaults and per-template settings are normalised for runtime use.

		private
		def normalise_site_pagination_source(raw_pagination)
			source = Utils.deep_copy(Utils.safe_hash(raw_pagination))

			syntax = Utils.safe_hash(source['syntax'])
			syntax['split'] = source['split'] if source.key?('split') && !syntax.key?('split')
			syntax['separator'] = source['separator'] if source.key?('separator') && !syntax.key?('separator')
			if source.key?('nested_key_separator') && !syntax.key?('separator') && !syntax.key?('nested_key_separator')
				syntax['separator'] = source['nested_key_separator']
			end
			source['syntax'] = syntax unless syntax.empty?

			templates = Utils.safe_hash(source['templates'])
			template_defaults = Utils.safe_hash(templates['defaults'])
			LEGACY_TEMPLATE_DEFAULT_KEYS.each do |legacy_key|
				next unless source.key?(legacy_key)
				next if template_defaults.key?(legacy_key)

				template_defaults[legacy_key] = source[legacy_key]
			end
			templates['defaults'] = template_defaults unless template_defaults.empty?
			source['templates'] = templates unless templates.empty?

			LEGACY_SITE_KEY_ALIASES.each { |legacy_key| source.delete(legacy_key) }
			LEGACY_TEMPLATE_DEFAULT_KEYS.each { |legacy_key| source.delete(legacy_key) }

			source
		end

		# Purpose: Normalises site common into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `config`, `compatibility_mode`, `raw_overrides`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_site_common!(config, compatibility_mode, raw_overrides = nil)
			config['enabled'] = !!config['enabled']
			config['debug'] = !!config['debug']
			config['compatibility'] = compatibility_mode if compatibility_mode

			config['syntax'] = normalise_syntax(config['syntax'])
			split_delimiter = config.dig('syntax', 'split')

			config['keywords'] = normalise_keywords(config['keywords'])
			config['equivalents'] = normalise_equivalents(config['equivalents'], split_delimiter)
			config['templates'] = normalise_templates(config['templates'], split_delimiter: split_delimiter, raw_overrides: raw_overrides)
		end

		# Resolves template syntax from local overrides, accepting both the
		# modern nested syntax hash and legacy root aliases.
		def resolve_template_syntax(raw_template_pagination, site_syntax)
			syntax = normalise_syntax(raw_template_pagination['syntax'], fallback: site_syntax)

			if raw_template_pagination.key?('split')
				syntax['split'] = normalise_split(raw_template_pagination['split'], syntax['split'])
			end

			if raw_template_pagination.key?('separator')
				separator = raw_template_pagination['separator'].to_s
				syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
			elsif raw_template_pagination.key?('nested_key_separator')
				separator = raw_template_pagination['nested_key_separator'].to_s
				syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
			end

			syntax
		end

		# Purpose: Normalises syntax into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_syntax`, `fallback`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_syntax(raw_syntax, fallback: nil)
			defaults = Utils.deep_copy(DEFAULTS['syntax'])
			defaults = defaults.merge(Utils.safe_hash(fallback)) if fallback.is_a?(Hash)
			syntax = defaults.merge(Utils.safe_hash(raw_syntax))

			separator = syntax['separator']
			if (separator.nil? || separator.to_s.strip.empty?) && syntax.key?('nested_key_separator')
				separator = syntax['nested_key_separator']
			end
			separator = defaults['separator'] if separator.to_s.strip.empty?

			{
				'separator' => separator.to_s,
				'split' => normalise_split(syntax['split'], defaults['split'])
			}
		end

		# Purpose: Normalises compatibility into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_value`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_compatibility(raw_value)
			value = raw_value.to_s.strip.downcase
			return nil if value.empty?
			return value if %w[v1 v2].include?(value)

			nil
		end

		# Purpose: Normalises split into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_split`, `default_split`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_split(raw_split, default_split = DEFAULTS.dig('syntax', 'split'))
			Utils.normalise_split_delimiter(raw_split, default_split)
		end

		# Purpose: Normalises keywords into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_keywords`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_keywords(raw_keywords)
			defaults = Utils.deep_copy(KEYWORD_DEFAULTS)
			keywords = defaults.merge(Utils.safe_hash(raw_keywords))

			keywords.each do |key, value|
				keywords[key] = value.to_s.strip
				keywords[key] = defaults[key] if keywords[key].empty?
			end

				invalid_keywords = keywords.select { |_, value| !value.match?(/\A[a-z]+\z/) }
				unless invalid_keywords.empty?
					raise ArgumentError, "pagination.keywords values must match [a-z]+. Invalid entries: #{invalid_keywords.map { |key, value| "#{key}=#{value}" }.join(', ')}."
				end

				duplicate_values = keywords.values.group_by { |value| value }.select { |_, values| values.length > 1 }.keys
				unless duplicate_values.empty?
					raise ArgumentError, "pagination.keywords values must be unique. Duplicates: #{duplicate_values.join(', ')}."
				end

			keywords
		end

		# Purpose: Normalises equivalents into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_equivalents`, `split_delimiter`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_equivalents(raw_equivalents, split_delimiter)
			return false if raw_equivalents == false

			groups = if raw_equivalents.is_a?(Array)
									raw_equivalents
								elsif raw_equivalents.nil?
									[]
								else
									[raw_equivalents]
								end
			return Utils.deep_copy(DEFAULTS['equivalents']) if groups.empty?

			groups.map do |group|
				entries = if group.is_a?(Array)
										group.flat_map { |entry| Utils.delimited_array(entry, delimiter: split_delimiter) }
									else
										Utils.delimited_array(group, delimiter: split_delimiter)
									end

				entries.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
			end.reject { |group| group.length < 2 }
		end

		# Purpose: Normalises templates into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_templates`, `split_delimiter`, `raw_overrides`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_templates(raw_templates, split_delimiter:, raw_overrides:)
			defaults = Utils.deep_copy(DEFAULTS['templates'])
			source = defaults.merge(Utils.safe_hash(raw_templates))

			source['location'] = defaults['location'] if source['location'].nil? || source['location'].to_s.strip.empty?
			source['generate'] = if source['generate'].is_a?(Array)
															source['generate'].map { |entry| Utils.safe_hash(entry) }
														elsif source['generate'].is_a?(Hash)
															[Utils.safe_hash(source['generate'])]
														else
															[]
														end

			merged_defaults = Jekyll::Utils.deep_merge_hashes(
				Utils.safe_hash(defaults['defaults']),
				Utils.safe_hash(source['defaults'])
			)
			source['defaults'] = normalise_template_defaults(
				merged_defaults,
				raw_overrides: extract_template_defaults_overrides(raw_overrides),
				split_delimiter: split_delimiter
			)

			source
		end

		# Extracts template-default override keys from either modern nested
		# config or legacy top-level aliases.
		def extract_template_defaults_overrides(raw_overrides)
			override_hash = Utils.safe_hash(raw_overrides)
			template_overrides = Utils.safe_hash(Utils.safe_hash(override_hash['templates'])['defaults'])

			LEGACY_TEMPLATE_DEFAULT_KEYS.each do |legacy_key|
				next unless override_hash.key?(legacy_key)
				next if template_overrides.key?(legacy_key)

				template_overrides[legacy_key] = override_hash[legacy_key]
			end

			template_overrides
		end

		# Normalises one template-default hash (used by site defaults and
		# by per-template runtime config).
		def normalise_template_defaults(template_defaults, raw_overrides:, split_delimiter:)
			config = Utils.safe_hash(template_defaults)
			template_override_hash = extract_template_defaults_overrides(raw_overrides)
			sort_explicitly_set = template_override_hash.key?('sort') && present_config_value?(template_override_hash['sort'])

			config['items'] = normalise_items_value(config['items'])
			config['filters'] = Utils.safe_hash(config['filters'])
			config['offset'] = [config['offset'].to_i, 0].max
			config['per_page'] = normalise_per_page(config['per_page'], split_delimiter: split_delimiter)
			config['limit'] = [config['limit'].to_i, 0].max
			config['permalink'] = config['permalink'].to_s
			config['title'] = config['title'].to_s
			config['trail'] = normalise_trail(config['trail'])
			config['sort'] = normalise_sort(
				config['sort'],
				config['sort_field'],
				config['sort_reverse'],
				split_delimiter,
				sort_explicitly_set: sort_explicitly_set
			)
			config['page_templates'] = build_page_templates(config['title'], config['permalink'])

			config.delete('sort_field')
			config.delete('sort_reverse')
			config.delete('indexpage')
			config.delete('extension')

			config
		end

		# Builds internal page template settings.
		#
		# Page 1 defaults to inheriting title/location from the source
		# template, while page 2+ uses configured paginator patterns.
		def build_page_templates(page2_title, page2_permalink)
			{
				'page1' => {
					'title' => ':title',
					'permalink' => ''
				},
				'page2' => {
					'title' => page2_title.to_s,
					'permalink' => page2_permalink.to_s
				}
			}
		end

		# Purpose: Normalises items value into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_items`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_items_value(raw_items)
			return DEFAULTS.dig('templates', 'defaults', 'items') if raw_items.nil?
			return raw_items if raw_items.is_a?(Hash) || raw_items.is_a?(Array)

			value = raw_items.to_s.strip
			value.empty? ? DEFAULTS.dig('templates', 'defaults', 'items') : value
		end

		# Purpose: Normalises trail into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_trail`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_trail(raw_trail)
			trail = Utils.safe_hash(raw_trail)
			{
				'before' => [trail['before'].to_i, 0].max,
				'after' => [trail['after'].to_i, 0].max
			}
		end

		# Normalises per-page configuration.
		#
		# Accepts:
		# - Integer-like values
		# - Array values
		# - Delimited strings (using configured split delimiter)
		#
		# Returns either:
		# - Integer, for single-size pagination
		# - Array<Integer>, for variable per-page pagination patterns
		def normalise_per_page(raw_per_page, split_delimiter:)
			if raw_per_page.is_a?(Array)
				return Utils.normalise_per_page_pattern(raw_per_page)
			end

			if raw_per_page.is_a?(String)
				split_values = Utils.delimited_array(raw_per_page, delimiter: split_delimiter)
				if split_values.length > 1
					return Utils.normalise_per_page_pattern(split_values)
				end
			end

			Utils.normalise_per_page_pattern(raw_per_page).first
		end

		# Preserves legacy `sort_field` + `sort_reverse` behaviour when the
		# caller did not provide an explicit `sort` override.
		def normalise_sort(raw_sort, raw_sort_field, raw_sort_reverse, split_delimiter, sort_explicitly_set: false)
			sort_entries = Utils.arrayify(raw_sort, split_delimiter: split_delimiter).map(&:to_s).map(&:strip).reject(&:empty?)
			sort_field = raw_sort_field.to_s.strip

			if !sort_explicitly_set && !sort_field.empty?
				direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
				return ["#{sort_field} #{direction}"]
			end

			return sort_entries unless sort_entries.empty?

			if sort_field.empty?
				fallback_sort = DEFAULTS.dig('templates', 'defaults', 'sort')
				return Utils.arrayify(fallback_sort, split_delimiter: split_delimiter).map(&:to_s).map(&:strip).reject(&:empty?)
			end

			direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
			["#{sort_field} #{direction}"]
		end

		# Migrates old v2 shorthand config into canonical template fields.
		# Modern keys retain precedence when both forms are supplied.
	end
end
end
end
end
end
