# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

# Nested frontmatter lookup helpers with equivalent-key support.
#
# Used by filtering, sorting, and index grouping for nested key reads.
module Utils
	
	# Splits a nested key according to configured separator.
	def self.split_nested_key(key, separator)
		Jekyll::Plugins::Support::FrontmatterPath.split_path(key, separator)
	end

	# Builds lookup table used for equivalent key resolution.
	# Each entry is keyed by full key-path string (for example
	# `product.tag`), which allows equivalent mappings to be scoped to one
	# nested level only.
	def self.build_equivalent_lookup(raw_equivalents, split_delimiter: ',')
		Jekyll::Plugins::Support::FrontmatterPath.build_equivalent_lookup(raw_equivalents, split_delimiter: split_delimiter)
	end

	# Resolves the effective hash key for one requested nested key path.
	# Equivalent lookups are performed using the full requested path; only
	# terminal segments from that matched group are candidates for hash
	# access at this level.
	def self.resolve_hash_key(hash, requested_key_path, equivalent_lookup, separator: '.')
		Jekyll::Plugins::Support::FrontmatterPath.resolve_hash_key(hash, requested_key_path, equivalent_lookup, separator: separator)
	end

	# Reads a value from hash by either string or symbol key.
	def self.read_hash(hash, key)
		Jekyll::Plugins::Support::FrontmatterPath.read_hash(hash, key)
	end

	# Retrieves all possible values from a nested key path.
	def self.fetch_nested_values(data, key_path, separator, equivalent_lookup)
		path_reader = Jekyll::Plugins::Support::FrontmatterPath.new(
			separator: separator,
			equivalent_lookup: equivalent_lookup
		)
		scalar_values(path_reader.traverse(data, key_path))
	end

	# Converts a mixed scalar/array value into a flat array of scalar values.
	def self.scalar_values(value)
		if value.is_a?(Array)
			value.flatten.compact
		elsif value.nil?
			[]
		else
			[value]
		end
	end
end

end
end
end
