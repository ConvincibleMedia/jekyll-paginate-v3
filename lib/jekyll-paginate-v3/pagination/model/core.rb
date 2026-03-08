# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Core pagination orchestration model.
#
# Responsibilities:
# - discover pagination templates
# - generate configured templates (`pagination.templates.generate`)
# - resolve and filter/sort items per template
# - emit paginated index pages/documents
#
# Used by Generators::PaginationGenerator as the main runtime
# coordinator for the pagination pipeline.
class Model

	def initialize(site:, site_config:, log_lambda:, add_item_lambda:, remove_item_lambda:)
		@site = site
		@site_config = site_config
		@log_lambda = log_lambda
		@add_item_lambda = add_item_lambda
		@remove_item_lambda = remove_item_lambda
		@nested_separator = site_config.dig('syntax', 'separator')
		@split_delimiter = site_config.dig('syntax', 'split')
		@equivalents = site_config['equivalents']
		@item_keyword = site_config.dig('keywords', 'items') || 'items'
		@generated_index_sets = {}
	end

	# Runs the full pagination pipeline for the current site build.
	def run
		@log_lambda.call("Pagination pipeline start: compatibility=#{@site_config['compatibility'] || 'none'} templates.location=#{@site_config.dig('templates', 'location')} generate.count=#{@site_config.dig('templates', 'generate')&.length || 0}", 'debug')

		generated_template_count = build_generated_templates
		@log_lambda.call("Generated #{generated_template_count} template(s).", 'debug')
		@log_lambda.call("Generated #{generated_template_count} pagination template(s) from `templates.generate`.", 'info') if generated_template_count.positive?

		templates = discover_templates
		if templates.empty?
			@log_lambda.call('Enabled, but no pagination templates were discovered.', 'warn')
			return 0
		end

		@log_lambda.call("Discovered #{templates.length} pagination template(s).", 'debug')
		enabled_templates = []
		disabled_templates = 0
		templates.each do |template|
			next unless template.data['pagination'].is_a?(Hash)

			template_config = Config::Normaliser.normalise_template_config(@site_config, template.data['pagination'])
			unless template_config['enabled']
				disabled_templates += 1
				@log_lambda.call("Skipping template '#{Utils.relative_item_path(template)}' because merged `pagination.enabled` is false.", 'debug')
				next
			end

			enabled_templates << [template, template_config]
		end

		if enabled_templates.empty?
			@log_lambda.call('Discovered pagination templates, but all resolved to `pagination.enabled: false` after config merge.', 'warn')
			return 0
		end

		@log_lambda.call("Processing #{enabled_templates.length} pagination template(s).", 'info')
		processed = 0
		enabled_templates.each do |template, template_config|

			@log_lambda.call("Paginating template '#{Utils.relative_item_path(template)}' with items=#{template_config['items']} filters=#{template_config['filters']}.", 'debug')
			begin
				paginate_template(template, template_config)
			rescue StandardError => error
				@log_lambda.call("Template '#{Utils.relative_item_path(template)}' failed: #{error.class}: #{error.message}", 'error')
				raise
			end
			processed += 1
		end

		apply_grouped_set_navigation!
		@log_lambda.call("Skipped #{disabled_templates} discovered template(s) because merged `pagination.enabled` is false.", 'debug') if disabled_templates.positive?

		@log_lambda.call("Pagination pipeline complete: processed #{processed} template(s).", 'debug')
		processed
	end

	private

	# Builds synthetic pagination templates from `templates.generate`.
	def build_generated_templates
		builder = Templates::Builder.new(
			site: @site,
			site_config: @site_config,
			add_item_lambda: @add_item_lambda,
			resolve_items_lambda: method(:resolve_items),
			log_lambda: @log_lambda
		)
		builder.build
	end

	# Discovers all pages/documents configured as pagination templates.
	def discover_templates
		candidates = resolve_items(
			@site_config.dig('templates', 'location'),
			include_templates: true,
			include_generated_indexes: true,
			include_hidden: true
		)

		discovery_counts = Hash.new(0)
		templates = candidates.select do |item|
			state = template_discovery_state(item)
			discovery_counts[state] += 1
			state == 'enabled'
		end
		@log_lambda.call(
			"Template discovery summary: candidates=#{candidates.length} enabled=#{discovery_counts['enabled']} disabled=#{discovery_counts['disabled']} missing_pagination=#{discovery_counts['missing_pagination']} invalid_data=#{discovery_counts['invalid_data']}.",
			'debug'
		)

		generated_templates = (@site.pages + all_collection_documents).select do |item|
			next false unless item.respond_to?(:data)
			next false unless item.data.is_a?(Hash)
			next false unless item.data.dig('paginate_v3', 'generated_template')

			template_discovery_state(item) == 'enabled'
		end
		@log_lambda.call("Template discovery: added #{generated_templates.length} generated template(s) outside configured search location.", 'debug') if generated_templates.any?

		templates.concat(generated_templates)
		templates.uniq!
		apply_implicit_v1_template_fallback(candidates, templates)
	end

	# Categorises a template candidate and marks enabled templates.
	def template_discovery_state(item)
		return 'invalid_data' unless item.respond_to?(:data)
		return 'invalid_data' unless item.data.is_a?(Hash)

		pagination = Utils.safe_hash(item.data['pagination'])
		return 'missing_pagination' if pagination.empty?
		return 'disabled' unless pagination['enabled']

		item.data['pagination'] = pagination
		item.data['pagination']['template'] = true
		'enabled'
	end

	# Provides an implicit v1 migration path when old `paginate` config
	# is present but no page has `pagination.enabled: true`.
	#
	# This keeps v1 compatibility focused on config migration while still
	# allowing the shared v3 pipeline to process the intended template.
	def apply_implicit_v1_template_fallback(candidates, templates)
		return templates unless templates.empty?
		return templates unless @site_config['compatibility'] == 'v1'
		return templates unless legacy_v1_site_config_present?

		template = legacy_v1_template_candidate(candidates)
		if template.nil?
			@log_lambda.call("v1 compatibility: no implicit template candidate matched paginate path '#{@site_config.dig('templates', 'permalink')}'.", 'warn')
			return templates
		end

		template.data['pagination'] = Utils.safe_hash(template.data['pagination'])
		template.data['pagination']['enabled'] = true
		template.data['pagination']['template'] = true

		@log_lambda.call("v1 compatibility: no explicit templates found; selected implicit template '#{Utils.relative_item_path(template)}'.", 'debug')
		[template]
	end

	# Detects whether the site includes the legacy v1 top-level config key.
	def legacy_v1_site_config_present?
		!@site.config['paginate'].nil?
	end

	# Selects the legacy v1 index page candidate as an implicit template.
	# The deepest matching `index.html` under the configured paginate path
	# hierarchy is preferred.
	def legacy_v1_template_candidate(items)
		source_root = File.expand_path(@site.config['source'].to_s)
		paginate_path = @site_config.dig('templates', 'permalink')

		items.select { |item| legacy_v1_pagination_candidate?(source_root, paginate_path, item) }.sort_by { |item| -item.path.to_s.size }.first
	end

	# Mirrors v1 template candidate detection rules for migration fallback.
	def legacy_v1_pagination_candidate?(source_root, paginate_path, item)
		return false unless item.respond_to?(:name)
		return false unless item.respond_to?(:path)
		return false if item.respond_to?(:collection) && !item.collection.nil?
		return false if Utils.generated_index?(item)
		return false unless item.name.to_s == 'index.html'

		page_dir = File.dirname(File.expand_path(Utils.remove_leading_slash(item.path), source_root))
		full_paginate_path = File.expand_path(Utils.remove_leading_slash(paginate_path), source_root)
		legacy_v1_in_hierarchy?(source_root, page_dir, File.dirname(full_paginate_path))
	end

	# Traverses parent directories to determine whether the page directory
	# is inside the legacy paginate path hierarchy.
	def legacy_v1_in_hierarchy?(source_root, page_dir, paginate_dir)
		source_parent = File.dirname(File.expand_path(source_root))
		current_dir = paginate_dir

		loop do
			return false if current_dir == File.dirname(current_dir)
			return false if current_dir == source_parent
			return true if page_dir == current_dir

			current_dir = File.dirname(current_dir)
		end
	end

	# Resolves the shared search format into concrete site items and then
	# applies generic inclusion/exclusion flags.
	def resolve_items(raw_search, include_templates: false, include_generated_indexes: false, include_hidden: false)
		entries = Query::Parser.parse(raw_search, @site_config['keywords'], split_delimiter: @split_delimiter)
		if entries.empty?
			@log_lambda.call("Resolving items from search=#{raw_search.inspect} produced no parsed entries.", 'debug')
			return []
		end

		@log_lambda.call("Resolving items from search=#{raw_search.inspect} (entries=#{entries.length}, include_templates=#{include_templates}, include_generated_indexes=#{include_generated_indexes}, include_hidden=#{include_hidden}).", 'debug')
		resolved = []
		entries.each do |entry|
			resolved.concat(resolve_entry(entry))
		end

		resolved.uniq!
		resolved.sort_by! { |item| Utils.relative_item_path(item) }
		@log_lambda.call("Resolved #{resolved.length} unique item(s) before exclusion filters.", 'debug')
		log_item_path_sample('Resolved item sample before exclusions', resolved)

		excluded_generated_indexes = include_generated_indexes ? 0 : resolved.count { |item| Utils.generated_index?(item) }
		excluded_templates = include_templates ? 0 : resolved.count { |item| Utils.pagination_template?(item) }
		excluded_hidden = include_hidden ? 0 : resolved.count { |item| item['hidden'] }

		resolved.select! { |item| !Utils.generated_index?(item) } unless include_generated_indexes
		resolved.select! { |item| !Utils.pagination_template?(item) } unless include_templates
		resolved.select! { |item| !item['hidden'] } unless include_hidden

		if excluded_generated_indexes.positive? || excluded_templates.positive? || excluded_hidden.positive?
			@log_lambda.call("Excluded generated_indexes=#{excluded_generated_indexes} templates=#{excluded_templates} hidden=#{excluded_hidden} from resolved items.", 'debug')
		end
		@log_lambda.call("Resolved #{resolved.length} item(s) after exclusion filters.", 'debug')
		log_item_path_sample('Resolved item sample after exclusions', resolved)
		resolved
	end

	# Resolves one parsed search entry (`pages`, collection label, etc).
	def resolve_entry(entry)
		type = entry['type']
		paths = entry['paths']
		source_items = source_items_for_entry_type(type)
		if source_items.nil?
			@log_lambda.call("Search entry type='#{type}' did not match pages/all/everything or a known collection; resolved 0 items.", 'warn')
			return []
		end

		@log_lambda.call("Resolving entry type='#{type}' paths=#{paths.inspect} from #{source_items.length} source item(s).", 'debug')
		matched_items = source_items.select do |item|
			Query::Parser.path_allowed?(Utils.relative_item_path(item), paths)
		end
		@log_lambda.call("Entry type='#{type}' matched #{matched_items.length}/#{source_items.length} item(s) after path filtering.", 'debug')
		log_item_path_sample("Entry type='#{type}' matched item sample", matched_items)
		matched_items
	end

	# Resolves source items for one parsed search entry type.
	def source_items_for_entry_type(type)
		case type
		when 'pages'
			@site.pages
		when 'all'
			all_collection_documents
		when 'everything'
			@site.pages + all_collection_documents
		else
			collection = @site.collections[type]
			return nil if collection.nil?

			collection.docs
		end
	end

	# Logs a compact sample of item paths for debug diagnostics.
	def log_item_path_sample(label, items, limit: 5)
		return if items.empty?

		maximum = [limit.to_i, 1].max
		sample_paths = items.first(maximum).map { |item| Utils.relative_item_path(item) }
		extra_count = items.length - sample_paths.length
		extra_suffix = extra_count.positive? ? " (+#{extra_count} more)" : ''
		@log_lambda.call("#{label}: #{sample_paths.join(', ')}#{extra_suffix}.", 'debug')
	end

	# Purpose: Implements all collection documents for this component.
	# Connects to: the surrounding pagination flow in this file.
	# Params: none.
	# Returns: a value consumed by the next pipeline step.
	def all_collection_documents
		@site.collections.values.flat_map(&:docs)
	end
end

end
end
end
end
