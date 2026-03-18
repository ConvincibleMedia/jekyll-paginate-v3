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
		overall_started_at = monotonic_seconds
		config = Config::Normaliser.normalise_site_config(site.config)
		config = enable_implicit_v1_compatibility(config, site)

		logger = Utils::Logger.new(debug_enabled: config['debug'])
		logger.debug("Normalised config summary: enabled=#{config['enabled']} compatibility=#{config['compatibility'] || 'none'} items=#{config['items']} templates.location=#{config.dig('templates', 'location')} generate.count=#{config.dig('templates', 'generate')&.length || 0}.")

		unless config['enabled']
			logger.info('Disabled in site config.')
			return
		end

		# Shared logger callback so deeper layers do not depend directly on
		# Jekyll logger globals.
		log_lambda = logger.method(:call)
		scoped_log_lambda_builder = logger.method(:scoped_log_lambda)

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
			scoped_log_lambda_builder: scoped_log_lambda_builder,
			add_item_lambda: add_item_lambda,
			remove_item_lambda: remove_item_lambda
		)

		run_report = model.run
		log_generate_report(logger, run_report['generated_template_report'])
		log_search_location_report(
			logger,
			run_report['search_location_report'],
			processed_templates: run_report['processed_templates'],
			search_duration_seconds: run_report['search_duration_seconds']
		)
		logger.info("Done in #{format_duration(monotonic_seconds - overall_started_at)}.")
	rescue StandardError => error
		if logger.nil?
			Jekyll.logger.error('Pagination:', "Failed with #{error.class}: #{error.message}")
		else
			logger.error("Failed with #{error.class}: #{error.message}")
		end
		raise
	end

	private

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

	# Logs the search summary as a readable multi-line block, including the
	# time spent locating pagination templates.
	def log_search_location_report(logger, search_location_report, processed_templates:, search_duration_seconds:)
		report_entries = Utils.arrayify(search_location_report)
		logger.info("Found #{processed_templates} #{pluralise('pagination template', processed_templates)} in #{format_duration(search_duration_seconds)}.")

		if report_entries.empty?
			logger.info("#{tree_branch(last_entry: true)} No template search locations were resolved.")
			return
		end

		location_width = report_entries.map { |entry| "#{entry['label']}:".length }.max || 0
		template_number_width = report_entries.map { |entry| entry['templates_found'].to_i.to_s.length }.max || 1
		index_number_width = report_entries.map { |entry| entry['indexes'].to_i.to_s.length }.max || 1
		item_number_width = report_entries.map { |entry| entry['paginated_items'].to_i.to_s.length }.max || 1
		template_noun_width = report_entries.map { |entry| count_noun(entry['templates_found'], singular: 'template', plural: 'templates').length }.max || 0
		index_noun_width = report_entries.map { |entry| count_noun(entry['indexes'], singular: 'index', plural: 'indexes').length }.max || 0
		item_noun_width = report_entries.map { |entry| count_noun(entry['paginated_items'], singular: 'total item', plural: 'total items').length }.max || 0

		entry_strings = report_entries.map do |entry|
			{
				'location' => "#{entry['label']}:",
				'template_count' => count_label(entry['templates_found'], singular: 'template', plural: 'templates', count_width: template_number_width, noun_width: template_noun_width),
				'index_count' => count_label(entry['indexes'], singular: 'index', plural: 'indexes', count_width: index_number_width, noun_width: index_noun_width),
				'item_count' => count_label(entry['paginated_items'], singular: 'total item', plural: 'total items', count_width: item_number_width, noun_width: item_noun_width)
			}
		end

		entry_strings.each_with_index do |entry, index|
			logger.info(search_report_line(
				location: entry['location'],
				template_count: entry['template_count'],
				index_count: entry['index_count'],
				item_count: entry['item_count'],
				location_width: location_width,
				last_entry: index == entry_strings.length - 1
			))
		end
	end

	# Formats elapsed seconds for human-readable logs without excessive
	# precision noise on short runs.
	def format_duration(duration_seconds)
		seconds = duration_seconds.to_f
		return format('%.3f seconds', seconds) if seconds < 1
		return format('%.2f seconds', seconds) if seconds < 10

		format('%.1f seconds', seconds)
	end

	# Returns the singular or plural noun phrase for one count.
	def pluralise(noun, count)
		count.to_i == 1 ? noun : "#{noun}s"
	end

	# Builds one count phrase using the singular or plural noun provided.
	def count_label(count, singular:, plural:, count_width:, noun_width:)
		count = count.to_i
		number_text = pad_left_for_logger(count.to_s, count_width)
		noun_text = pad_for_logger(count_noun(count, singular: singular, plural: plural), noun_width)
		"#{number_text} #{noun_text}"
	end

	# Resolves the singular or plural noun for one count label.
	def count_noun(count, singular:, plural:)
		count.to_i == 1 ? singular : plural
	end

	# Builds one aligned search-report line. Jekyll collapses ordinary
	# whitespace inside log messages, so alignment padding uses
	# non-breaking spaces generated at runtime.
	def search_report_line(location:, template_count:, index_count:, item_count:, location_width:, last_entry:)
		"#{tree_branch(last_entry: last_entry)} #{pad_for_logger(location, location_width)} #{template_count} became #{index_count} with #{item_count}"
	end

	# Returns the tree glyph prefix for one report line.
	def tree_branch(last_entry:)
		last_entry ? '└─' : '├─'
	end

	# Pads one visible segment with non-breaking spaces so Jekyll's logger
	# preserves report alignment.
	def pad_for_logger(text, width)
		text = text.to_s
		return text if text.length >= width

		text + (non_breaking_space * (width - text.length))
	end

	# Left-pads one visible segment with non-breaking spaces so numbers can
	# be right-aligned in Jekyll logger output.
	def pad_left_for_logger(text, width)
		text = text.to_s
		return text if text.length >= width

		(non_breaking_space * (width - text.length)) + text
	end

	# Returns one non-breaking space character without embedding
	# non-ASCII text directly into the source file.
	def non_breaking_space
		@non_breaking_space ||= [160].pack('U')
	end

	# Returns a monotonic timestamp suitable for elapsed-duration
	# measurements that should not be affected by wall-clock changes.
	def monotonic_seconds
		Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
