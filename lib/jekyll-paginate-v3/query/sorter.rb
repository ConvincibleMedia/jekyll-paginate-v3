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
	def self.apply(items, raw_sort, nested_separator:, equivalents:, split_delimiter: ',')
		instructions = parse(raw_sort, split_delimiter: split_delimiter)
		return items if instructions.empty?

		frontmatter_path = Jekyll::Plugins::Support::FrontmatterPath.new(
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
	def self.parse(raw_sort, split_delimiter: ',')
		entries = Utils.arrayify(raw_sort, split_delimiter: split_delimiter).map { |entry| entry.to_s.strip }.reject(&:empty?)

		entries.map do |entry|
			fragments = entry.split(/\s+/)
			field = fragments.shift.to_s.strip
			next nil if field.empty?

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

			{
				'field' => field,
				'direction' => direction,
				'empty' => empty
			}
		end.compact
	end

	class << self
		private

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
			left_value = first_field_value(left_item, instruction['field'], frontmatter_path)
			right_value = first_field_value(right_item, instruction['field'], frontmatter_path)

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
