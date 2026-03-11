# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Generators

# Jekyll generator entry point for paginate-v3.
#
# Used by Jekyll's generator lifecycle to invoke the v3 pagination
# pipeline for each site build.
class PaginationGenerator < Jekyll::Generator

	safe true
	priority :lowest

	# Entrypoint called by Jekyll once the site graph is loaded.
	#
	# Normalises config, wires lightweight callbacks for mutating site
	# content, then delegates all pagination behaviour to Pagination::Model.
	def generate(site)
		logger = nil
		config = Config::Normaliser.normalise_site_config(site.config)
		config = enable_implicit_v1_compatibility(config, site)

		logger = Utils::Logger.new(debug_enabled: config['debug'])
		logger.debug("Normalised config summary: enabled=#{config['enabled']} compatibility=#{config['compatibility'] || 'none'} items=#{config['items']} templates.location=#{config.dig('templates', 'location')} generate.count=#{config.dig('templates', 'generate')&.length || 0}.")

		unless config['enabled']
			logger.info('Disabled in site config.')
			return
		end
		logger.info("Enabled. Will look for templates in: #{template_location_summary(config)}")

		# Shared logger callback so deeper layers do not depend directly on
		# Jekyll logger globals.
		log_lambda = logger.method(:call)

		# Abstract site mutation so the model can add pages or documents
		# without knowing where Jekyll stores each item type.
		add_item_lambda = lambda do |item|
			if item.is_a?(Jekyll::Document)
				site.collections[item.collection.label].docs << item
			else
				site.pages << item
			end
			item
		end

		# Mirror add_item_lambda for replacing template pages with generated
		# paginated siblings.
		remove_item_lambda = lambda do |item|
			if item.is_a?(Jekyll::Document)
				site.collections[item.collection.label].docs.delete_if { |doc| doc == item }
			else
				site.pages.delete_if { |page| page == item }
			end
		end

		model = Pagination::Model.new(
			site: site,
			site_config: config,
			log_lambda: log_lambda,
			add_item_lambda: add_item_lambda,
			remove_item_lambda: remove_item_lambda
		)

		run_report = model.run
		log_generate_report(logger, run_report['generated_template_report'])
		log_search_location_report(logger, run_report['search_location_report'], processed_templates: run_report['processed_templates'])
	rescue StandardError => error
		if logger.nil?
			Jekyll.logger.error('Pagination:', "Failed with #{error.class}: #{error.message}")
		else
			logger.error("Failed with #{error.class}: #{error.message}")
		end
		raise
	end

	private

	# Formats the configured template search locations for info-level logs.
	def template_location_summary(config)
		search_entries = Query::Parser.parse(
			config.dig('templates', 'location'),
			config['keywords'],
			split_delimiter: config.dig('syntax', 'split')
		)
		return '(none)' if search_entries.empty?

		search_entries.map { |entry| Query::Parser.entry_label(entry) }.join(', ')
	end

	# Logs one info-level summary line for each configured generate entry.
	def log_generate_report(logger, generated_template_report)
		report_entries = Utils.arrayify(generated_template_report['entries'])
		return if report_entries.empty?

		segments = report_entries.map do |entry|
			location_label = generated_template_location_label(entry['collection'])
			invalid_suffix = entry['valid'] ? '' : ' (invalid config)'
			"##{entry['number']}: #{entry['created']} template(s) in #{location_label}#{invalid_suffix}"
		end

		logger.info("Generate report: #{segments.join('; ')}")
	end

	# Converts a generated-template destination location into readable text.
	def generated_template_location_label(collection_targets)
		targets = Utils.arrayify(collection_targets).map(&:to_s).map(&:strip).reject(&:empty?)
		targets = ['pages'] if targets.empty?
		return target_label(targets.first) if targets.length == 1

		"page1=#{target_label(targets.first)} page2+=#{target_label(targets[1])}"
	end

	# Converts one collection target token to a readable log label.
	def target_label(target)
		return 'pages (site root)' if target == 'pages'

		"collection '#{target}'"
	end

	# Logs one info-level summary line for search-location discovery and totals.
	def log_search_location_report(logger, search_location_report, processed_templates:)
		report_entries = Utils.arrayify(search_location_report)
		if report_entries.empty?
			logger.info("Search report: no location entries were resolved. processed=#{processed_templates} template(s).")
			return
		end

		segments = report_entries.map do |entry|
			"#{entry['label']}: templates=#{entry['templates_found']} items=#{entry['paginated_items']} indexes=#{entry['indexes']}"
		end

		total_templates_found = report_entries.inject(0) { |sum, entry| sum + entry['templates_found'].to_i }
		total_paginated_items = report_entries.inject(0) { |sum, entry| sum + entry['paginated_items'].to_i }
		total_indexes = report_entries.inject(0) { |sum, entry| sum + entry['indexes'].to_i }
		logger.info("Search report: #{segments.join('; ')}. totals: templates=#{total_templates_found} items=#{total_paginated_items} indexes=#{total_indexes} processed=#{processed_templates}.")
	end

	# Convenience bridge for old jekyll-paginate sites that still define
	# `paginate`/`paginate_path` without explicit v3 config.
	def enable_implicit_v1_compatibility(config, site)
		return config unless config['compatibility'].nil?
		return config unless legacy_v1_site_config_present?(site)

		Jekyll.logger.warn('Pagination:', 'Detected legacy `paginate` config; enabling `compatibility: v1` automatically.')

		adjusted = Jekyll::Utils.deep_merge_hashes(site.config, {
			'pagination' => {
				'compatibility' => 'v1'
			}
		})

		Config::Normaliser.normalise_site_config(adjusted)
	end

	# Detects whether the site includes the legacy v1 top-level config key.
	def legacy_v1_site_config_present?(site)
		!site.config['paginate'].nil?
	end
end

end
end
end
end
