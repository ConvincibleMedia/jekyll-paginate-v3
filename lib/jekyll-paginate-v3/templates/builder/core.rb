# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Builds generated pagination templates from `pagination.templates.generate`.
#
# Generate definitions now describe the `pagination` config that should be
# applied to the generated template. Grouping/layout expansion is handled
# later by runtime template processing.
class Builder

	SPECIAL_KEYS = %w[frontmatter content].freeze

	def initialize(site:, site_config:, add_item_lambda:, resolve_items_lambda:, log_lambda:)
		@site = site
		@site_config = site_config
		@add_item_lambda = add_item_lambda
		@resolve_items_lambda = resolve_items_lambda
		@log_lambda = log_lambda
		@split_delimiter = site_config.dig('syntax', 'split')
		@compatibility_mode = site_config['compatibility']
	end

	# Builds all configured generated pagination templates.
	def build
		generate_definitions = @site_config.dig('templates', 'generate')
		return empty_build_report unless generate_definitions.is_a?(Array)

		@log_lambda.call("Generating templates from #{generate_definitions.length} definition(s).", 'debug')
		default_collection = default_generation_collection
		@log_lambda.call("Default generated template collection target resolved to '#{default_collection.join(',')}'.", 'debug')
		build_report = {
			'total' => 0,
			'entries' => []
		}

		generate_definitions.each_with_index do |raw_definition, definition_index|
			entry_number = definition_index + 1
			default_entry_collection = normalise_collection(Utils.safe_hash(raw_definition)['collection'], default_collection)
			definition = normalise_definition(raw_definition, default_collection)
			if definition.nil?
				build_report['entries'] << {
					'number' => entry_number,
					'collection' => default_entry_collection,
					'created' => 0,
					'valid' => false
				}
				next
			end

			@log_lambda.call("Processing generate definition #{entry_number}: collection=#{definition['template_collection'].join(',')} pagination_keys=#{definition['pagination'].keys.sort.join(',')}", 'debug')
			created_template = build_template(definition)
			created = 0
			unless created_template.nil?
				@add_item_lambda.call(created_template)
				created = 1
			end
			build_report['entries'] << {
				'number' => entry_number,
				'collection' => definition['template_collection'],
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

	# Builds one generated template object from one generate definition.
	def build_template(definition)
		generated_metadata = {
			'generated_template' => true,
			'compatibility' => @compatibility_mode
		}

		pagination_config = Utils.deep_copy(definition['pagination'])
		pagination_config['enabled'] = true

		first_target = definition['template_collection'].first
		if first_target == 'pages'
			Templates::PageTemplate.new(
				site: @site,
				pagination_config: pagination_config,
				frontmatter: definition['frontmatter'],
				content: definition['content'],
				generated_metadata: generated_metadata
			)
		else
			collection = @site.collections[first_target]
			if collection.nil?
				@log_lambda.call("Skipping generated template in unknown collection '#{first_target}'.", 'warn')
				return nil
			end

			Templates::DocumentTemplate.new(
				site: @site,
				collection: collection,
				pagination_config: pagination_config,
				frontmatter: definition['frontmatter'],
				content: definition['content'],
				generated_metadata: generated_metadata
			)
		end
	rescue StandardError => error
		@log_lambda.call("Unable to generate template: #{error.message}", 'warn')
		nil
	end
end

end
end
end
end
