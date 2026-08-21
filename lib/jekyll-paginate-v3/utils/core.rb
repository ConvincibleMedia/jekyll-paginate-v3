# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

# Core helpers shared across config, query, and pagination layers.
#
# Used broadly by normalisers, builders, and parsers.
module Utils

	# Deep copy helper for plain Ruby hashes/arrays used in config merging.
	def self.deep_copy(value)
		if value.is_a?(Hash)
			value.each_with_object({}) { |(key, child), copy| copy[key] = deep_copy(child) }
		elsif value.is_a?(Array)
			value.map { |child| deep_copy(child) }
		else
			value
		end
	end

	# Normalises a configurable delimiter.
	# Returns `default_delimiter` when the input is blank or unsupported.
	#
	# `false` disables delimited splitting globally.
	def self.normalise_split_delimiter(raw_delimiter, default_delimiter = ',')
		Jekyll::Plugins::PaginateV3::Support::StringArray.normalise_delimiter(raw_delimiter, default_delimiter)
	end

	# Splits one string using the configured delimiter, trims entries, and rejects blank strings.
	def self.split_delimited_string(value, delimiter)
		Jekyll::Plugins::PaginateV3::Support::StringArray.new(delimiter: delimiter).interpret(value, split: 0, flatten: true)
	end

	# Converts scalars/arrays into a flat array and applies delimited-string expansion for all string entries.
	def self.delimited_array(value, delimiter: ',')
		Jekyll::Plugins::PaginateV3::Support::StringArray.new(delimiter: delimiter).interpret(value, split: -1, flatten: true)
	end

	# Converts a value into an array. Strings can be treated as delimiter-defined lists.
	def self.arrayify(value, split_commas: false, split_delimiter: nil)
		delimiter = split_delimiter
		delimiter = ',' if delimiter.nil? && split_commas

		Jekyll::Plugins::PaginateV3::Support::StringArray.new(delimiter: delimiter || ',').interpret(
			value,
			split: delimiter.nil? ? false : 0,
			flatten: true,
			delimiter: delimiter.nil? ? Jekyll::Plugins::PaginateV3::Support::StringArray::UNSET : delimiter
		)
	end

	# Normalises hash keys recursively to strings.
	def self.stringify_keys(value)
		return value unless value.is_a?(Hash)

		value.each_with_object({}) do |(key, child), copy|
			copy[key.to_s] = child.is_a?(Hash) ? stringify_keys(child) : child
		end
	end

	# Returns a hash from any input object, or an empty hash for unsupported values.
	def self.safe_hash(value)
		value.is_a?(Hash) ? stringify_keys(value) : {}
	end

	# Backwards-compatible alias for comma-delimited list parsing.
	def self.comma_delimited_array(value)
		delimited_array(value, delimiter: ',').map { |entry| entry.to_s.strip }.reject(&:empty?)
	end

	# Expands `layout` + `layouts` config into a unique array of layout names.
	def self.normalise_layouts(config, split_delimiter: ',')
		source = safe_hash(config)
		layouts = []
		layouts.concat(arrayify(source['layouts'], split_delimiter: split_delimiter)) if source.key?('layouts')
		layouts.concat(arrayify(source['layout'], split_delimiter: split_delimiter)) if source.key?('layout')
		layouts.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
	end

	# Returns a Jekyll layout key while preserving nested layout directories
	# and accepting an optional filename extension on the final segment.
	def self.normalise_layout_name(value)
		layout_name = value.to_s.strip
		return layout_name if layout_name.empty?

		extension = File.extname(layout_name)
		return layout_name if extension.empty?

		layout_name[0...-extension.length]
	end

	# Merges generated-template pagination config with layout pagination.
	#
	# Default behaviour matches normal Jekyll precedence semantics: generated template config overrides layout defaults.
	#
	# In v2 compatibility mode we retain legacy override order, but strip layout `enabled` so generated templates cannot be disabled by layout frontmatter.
	def self.merge_generated_template_pagination(generated_pagination, layout_pagination, compatibility_mode)
		generated_hash = safe_hash(generated_pagination)
		layout_hash = safe_hash(layout_pagination)

		if compatibility_mode == 'v2'
			layout_hash.delete('enabled')
			return Jekyll::Utils.deep_merge_hashes(generated_hash, layout_hash)
		end

		Jekyll::Utils.deep_merge_hashes(layout_hash, generated_hash)
	end
end

end
end
end
