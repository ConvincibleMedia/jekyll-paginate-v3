# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query

# Multi-level sorter for v3 `sort` definitions.
#
# Example definitions:
# - `sort: date desc`
# - `sort: owner.name, date desc empty:first` (delimiter is configurable)
# - `sort: ["featured desc", "date desc"]`
#
# Used by Pagination::Model to apply deterministic item ordering.
class Sorter

	# Applies parsed sort instructions while preserving input order as a
	# final deterministic tiebreak.
	def self.apply(items, raw_sort, nested_separator:, equivalents:, split_delimiter: ',', instructions: nil)
		instructions ||= parse(
			raw_sort,
			split_delimiter: split_delimiter,
			nested_separator: nested_separator,
			structural: true
		)
		return items if instructions.empty?

		frontmatter_path = Jekyll::Plugins::PaginateV3::Support::FrontmatterPath.new(
			separator: nested_separator,
			arrays: :expand,
			equivalents: equivalents
		)

		# Keep original index as final tiebreak so ordering remains predictable.
		indexed_items = items.each_with_index.to_a
		indexed_items.sort! do |(left_item, left_index), (right_item, right_index)|
			comparison = compare_items(left_item, right_item, instructions, frontmatter_path)
			comparison.zero? ? left_index <=> right_index : comparison
		end

		indexed_items.map(&:first)
	end

	# Parses `sort` config entries into normalised field instructions.
	#
	# Group values are bound before path splitting and emitted as structural
	# segments when `structural` is enabled. This keeps separators contained in
	# raw group values from becoming new frontmatter path boundaries.
	def self.parse(raw_sort, split_delimiter: ',', nested_separator: '.', group_keys: [], group_values: nil, structural: false, context: 'sort instruction')
		entries = sort_entries(raw_sort, split_delimiter)

		entries.map do |entry|
			fragments = Support::PlaceholderTemplate.split_whitespace(entry)
			field_source = fragments.shift.to_s.strip
			next nil if field_source.empty?

			field_template = Utils.placeholder_template(
				field_source,
				allowed: group_keys,
				context: context
			)

			direction = 'asc'
			empty = 'last'

			fragments.each do |fragment|
				token = fragment.to_s.strip.downcase
				case token
				when 'asc', 'ascending'
					direction = 'asc'
				when 'desc', 'descending'
					direction = 'desc'
				else
					if token.start_with?('empty:')
						empty_value = token.split(':', 2).last
						empty = %w[first last].include?(empty_value) ? empty_value : empty
					end
				end
			end

			instruction = {
				'field' => field_source,
				'direction' => direction,
				'empty' => empty
			}

			if structural
				bound_field = field_template.bind(
					group_values || {},
					default_representation: :slugify
				)
				segments = bound_field.split(nested_separator).map do |segment|
					segment.render({}, default_representation: :slugify, unresolved: :error).strip
				end.reject(&:empty?)
				instruction['source_field'] = field_source
				instruction['field_segments'] = segments
				instruction['field'] = segments.join(nested_separator.to_s)
			end

			instruction
		end.compact
	end

	# Validates grouped sort placeholders before item-dependent variants are
	# created, ensuring configuration errors also fail on empty sites.
	def self.validate_placeholders!(raw_sort, group_keys:, split_delimiter: ',', context: 'sort instruction')
		parse(
			raw_sort,
			split_delimiter: split_delimiter,
			group_keys: group_keys,
			context: context
		)
		true
	end

	class << self
		private

		# Expands array or delimited scalar sort definitions without splitting
		# canonical filter pipes or other text inside placeholder expressions.
		def sort_entries(raw_sort, split_delimiter)
			raw_entries = raw_sort.is_a?(Array) ? raw_sort.flatten : [raw_sort]
			raw_entries.flat_map do |raw_entry|
				Support::PlaceholderTemplate.split_source(
					raw_entry,
					delimiter: split_delimiter
				)
			end.map { |entry| entry.to_s.strip }.reject(&:empty?)
		end

		# Purpose: Compares items for ordering decisions.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `left_item`, `right_item`, `instructions`, `nested_separator`, `equivalent_lookup`.
		# Returns: a value consumed by the next pipeline step.
		def compare_items(left_item, right_item, instructions, frontmatter_path)
			instructions.each do |instruction|
				comparison = compare_field(left_item, right_item, instruction, frontmatter_path)
				return comparison unless comparison.zero?
			end

			0
		end

		# Purpose: Compares field for ordering decisions.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `left_item`, `right_item`, `instruction`, `nested_separator`, `equivalent_lookup`.
		# Returns: a value consumed by the next pipeline step.
		def compare_field(left_item, right_item, instruction, frontmatter_path)
			field = instruction['field_segments'] || instruction['field']
			left_value = first_field_value(left_item, field, frontmatter_path)
			right_value = first_field_value(right_item, field, frontmatter_path)

			left_empty = empty_value?(left_value)
			right_empty = empty_value?(right_value)

			if left_empty || right_empty
				return 0 if left_empty && right_empty

				if instruction['empty'] == 'first'
					return left_empty ? -1 : 1
				end

				return left_empty ? 1 : -1
			end

			rank_comparison = value_rank(left_value) <=> value_rank(right_value)
			return direction_adjust(rank_comparison, instruction['direction']) unless rank_comparison.zero?

			value_comparison = compare_ranked_values(left_value, right_value)
			direction_adjust(value_comparison, instruction['direction'])
		end

		# Purpose: Implements first field value for this component.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `item`, `field`, `nested_separator`, `equivalent_lookup`.
		# Returns: a value consumed by the next pipeline step.
		def first_field_value(item, field, frontmatter_path)
			data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}

			collection_label = Utils.item_collection_label(item)
			data['collection'] = collection_label unless collection_label.nil?

			Utils.scalar_values(frontmatter_path.traverse(data, field)).first
		end

		# Purpose: Implements empty value for this component.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `value`.
		# Returns: `true` or `false`.
		def empty_value?(value)
			value.nil? || (value.respond_to?(:empty?) && value.empty?)
		end

		# Purpose: Implements value rank for this component.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `value`.
		# Returns: a value consumed by the next pipeline step.
		def value_rank(value)
			return 0 if value == true
			return 1 if value == false
			return 2 if value.is_a?(Numeric)

			3
		end

		# Purpose: Compares ranked values for ordering decisions.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `left`, `right`.
		# Returns: a value consumed by the next pipeline step.
		def compare_ranked_values(left, right)
			rank = value_rank(left)

			case rank
			when 0, 1
				0
			when 2
				left.to_f <=> right.to_f
			else
				left.to_s.downcase <=> right.to_s.downcase
			end
		end

		# Purpose: Implements direction adjust for this component.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `comparison`, `direction`.
		# Returns: a value consumed by the next pipeline step.
		def direction_adjust(comparison, direction)
			direction == 'desc' ? -comparison : comparison
		end
	end
end

end
end
end
end
