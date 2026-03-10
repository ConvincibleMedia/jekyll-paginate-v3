# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Builds generated pagination templates from `pagination.templates.generate`.
#
# Generated templates are ordinary pages/documents with
# `pagination.enabled: true`, so the core pagination model can process
# them exactly like hand-written pagination templates.
#
# Used by Pagination::Model before normal page pagination starts.
class Builder

	SPECIAL_KEYS = %w[items index filter filters group layout layouts location frontmatter permalink title slugify silent allow_empty].freeze

	def initialize(site:, site_config:, add_item_lambda:, resolve_items_lambda:, log_lambda:)
		@site = site
		@site_config = site_config
		@add_item_lambda = add_item_lambda
		@resolve_items_lambda = resolve_items_lambda
		@log_lambda = log_lambda
		@nested_separator = site_config.dig('syntax', 'separator')
		@split_delimiter = site_config.dig('syntax', 'split')
		@equivalents = site_config['equivalents']
		@compatibility_mode = site_config['compatibility']
	end

	# Builds all configured generated pagination templates.
	def build
		generate_definitions = @site_config.dig('templates', 'generate')
		return empty_build_report unless generate_definitions.is_a?(Array)

		@log_lambda.call("Generating templates from #{generate_definitions.length} definition(s).", 'debug')
		default_location = default_generation_location
		@log_lambda.call("Default generated template location resolved to '#{default_location}'.", 'debug')
		build_report = {
			'total' => 0,
			'entries' => []
		}

		generate_definitions.each_with_index do |raw_definition, definition_index|
			entry_number = definition_index + 1
			default_entry_location = normalise_location(Utils.safe_hash(raw_definition)['location'], default_location)
			definition = normalise_definition(raw_definition, default_location)
			if definition.nil?
				build_report['entries'] << {
					'number' => entry_number,
					'location' => default_entry_location,
					'created' => 0,
					'valid' => false
				}
				next
			end

			@log_lambda.call("Processing generate definition #{entry_number}: index=#{describe_index_keys(definition['index'])} items=#{definition['items']} layouts=#{definition['layouts'].join(', ')} location=#{definition['location']} allow_empty=#{definition['allow_empty']}", 'debug')
			source_items = @resolve_items_lambda.call(definition['items'])
			@log_lambda.call("Definition #{entry_number} resolved #{source_items.length} source item(s) before filters.", 'debug')
			source_items = Query::Filter.filter_items(
				source_items,
				definition['filters'],
				nested_separator: @nested_separator,
				equivalents: @equivalents,
				split_delimiter: @split_delimiter,
				now_keyword: @site_config.dig('keywords', 'now'),
				today_keyword: @site_config.dig('keywords', 'today'),
				log_lambda: @log_lambda,
				context_label: "Generated definition #{entry_number}"
			)
			@log_lambda.call("Definition #{entry_number} retained #{source_items.length} source item(s) after filters.", 'debug')

			created = build_for_definition(definition, source_items, entry_number)
			build_report['entries'] << {
				'number' => entry_number,
				'location' => definition['location'],
				'created' => created,
				'valid' => true
			}
			build_report['total'] += created
		end

		@log_lambda.call("Generated #{build_report['total']} template object(s) in total.", 'debug')
		build_report
	end

	private

	# Provides a stable zero-value build report when generation is disabled.
	def empty_build_report
		{
			'total' => 0,
			'entries' => []
		}
	end

	# Expands one generate definition into concrete template pages/documents.
	def build_for_definition(definition, source_items, definition_number)
		entries = build_index_entries(source_items, definition)
		if entries.empty?
			@log_lambda.call("No index entries were generated for index=#{describe_index_keys(definition['index'])}.", 'debug')
			return 0
		end

		@log_lambda.call("Expanded to #{entries.length} index key combination(s) for index=#{describe_index_keys(definition['index'])}.", 'debug')

		created = 0

		entries.each do |entry|
			definition['layouts'].each do |layout_name|
				page = build_template(
					definition,
					entry,
					layout_name,
					definition_number: definition_number
				)
				next if page.nil?

				@add_item_lambda.call(page)
				@log_lambda.call("Created generated template for layout='#{layout_name}' values=#{entry['values']}.", 'debug')
				created += 1
			end
		end

		created
	end

	# Builds a single template object for one index value tuple and layout.
	def build_template(definition, entry, layout_name, definition_number:)
		token_maps = build_token_maps(definition['index'], entry, slugify_config: definition['slugify'])
		generated_permalink = Utils.replace_tokens(definition['permalink'], token_maps['permalink'])
		generated_title = Utils.replace_tokens(definition['title'], token_maps['title'])
		generated_metadata = build_generated_metadata(
			definition['index'],
			entry['values'],
			token_maps['compatibility'],
			group_levels: build_group_level_metadata(entry, definition_number, layout_name)
		)

		generated_frontmatter = Utils.deep_copy(definition['frontmatter'])
		generated_frontmatter['title'] = generated_title unless generated_title.nil? || generated_title.empty?
		generated_frontmatter['permalink'] = generated_permalink unless generated_permalink.nil? || generated_permalink.empty?

		pagination_config = Utils.deep_copy(definition['pagination_overrides'])
		pagination_config['enabled'] = true
		pagination_config['items'] = definition['items']
		pagination_config['filters'] = Utils.deep_copy(definition['filters']).merge(entry['filters'])

		if definition['location'] == 'pages'
			Templates::PageTemplate.new(
				site: @site,
				layout_name: layout_name,
				pagination_config: pagination_config,
				frontmatter: generated_frontmatter,
				generated_metadata: generated_metadata
			)
		else
			collection = @site.collections[definition['location']]
			if collection.nil?
				@log_lambda.call("Skipping generated template in unknown collection '#{definition['location']}'.", 'warn') unless definition['silent']
				return nil
			end

			Templates::DocumentTemplate.new(
				site: @site,
				collection: collection,
				layout_name: layout_name,
				pagination_config: pagination_config,
				frontmatter: generated_frontmatter,
				generated_metadata: generated_metadata
			)
		end
	rescue StandardError => error
		@log_lambda.call("Unable to generate template from layout '#{layout_name}': #{error.message}", 'warn') unless definition['silent']
		nil
	end
end

end
end
end
end
