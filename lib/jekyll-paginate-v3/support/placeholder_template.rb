# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Support

# Parses and resolves the deliberately small placeholder language used by PV3.
#
# Canonical Liquid-shaped expressions and greedy legacy colon tokens both become
# the same nodes. Bound values are opaque literals so later parsing and path
# splitting cannot reinterpret text supplied by a placeholder.
class PlaceholderTemplate

	FILTERS = %w[raw slugify].freeze
	FILTERLESS_PLACEHOLDERS = %w[num max].freeze
	UNKNOWN_ERROR = :error
	UNKNOWN_PRESERVE = :preserve

	# Holds the two supported representations of one plugin-provided value.
	class Value
		attr_reader :raw, :slugified

		def initialize(raw:, slugified: nil, raw_available: true)
			@raw = raw
			@slugified = slugified
			@raw_available = raw_available
		end

		# Resolves the selected representation without reparsing the result.
		def resolve(representation, slugifier:, name:, context:)
			if representation == 'raw'
				unless @raw_available
					raise ArgumentError, "Placeholder '#{name}' cannot use its raw representation in #{context} because the group contains multiple raw values with the same slug."
				end

				return @raw.to_s
			end

			return @slugified.to_s unless @slugified.nil?

			slugifier.call(@raw).to_s
		end
	end

	# Literal source text. Bound placeholder values are marked unsplittable.
	class LiteralNode
		attr_reader :text

		def initialize(text, splittable: true)
			@text = text.to_s
			@splittable = splittable
		end

		def splittable?
			@splittable
		end
	end

	# One validated placeholder reference.
	class PlaceholderNode
		attr_reader :name, :filter, :syntax, :source

		def initialize(name:, filter:, syntax:, source:)
			@name = name
			@filter = filter
			@syntax = syntax
			@source = source
		end
	end

	attr_reader :context, :style

	# Parses one scalar against the placeholders explicitly available there.
	def self.parse(source, allowed:, context:, allowed_filters: nil, unknown: UNKNOWN_ERROR)
		new(source: source, allowed: allowed, context: context, allowed_filters: allowed_filters, unknown: unknown)
	end

	# Splits a scalar on one delimiter while protecting canonical expressions.
	# This is used before the context-specific placeholder allowlist is known.
	def self.split_source(source, delimiter:, limit: nil)
		text = source.to_s
		separator = delimiter.to_s
		return [text] if separator.empty?

		parts = [String.new]
		inside_expression = false
		index = 0
		while index < text.length
			if !inside_expression && text[index, 2] == '{{'
				inside_expression = true
				parts.last << '{{'
				index += 2
				next
			end

			if inside_expression && text[index, 2] == '}}'
				inside_expression = false
				parts.last << '}}'
				index += 2
				next
			end

			can_split = !inside_expression && text[index, separator.length] == separator
			can_split &&= limit.nil? || parts.length < limit
			if can_split
				parts << String.new
				index += separator.length
			else
				parts.last << text[index]
				index += 1
			end
		end

		parts
	end

	# Splits sort syntax on whitespace outside canonical expressions.
	def self.split_whitespace(source, limit: nil)
		text = source.to_s
		parts = []
		current = String.new
		inside_expression = false
		index = 0

		while index < text.length
			if !inside_expression && text[index, 2] == '{{'
				inside_expression = true
				current << '{{'
				index += 2
				next
			end

			if inside_expression && text[index, 2] == '}}'
				inside_expression = false
				current << '}}'
				index += 2
				next
			end

			can_split = !inside_expression && text[index] =~ /\s/
			can_split &&= limit.nil? || parts.length < limit - 1
			if can_split
				parts << current unless current.empty?
				current = String.new
				index += 1
				index += 1 while index < text.length && text[index] =~ /\s/
			else
				current << text[index]
				index += 1
			end
		end

		parts << current unless current.empty?
		parts
	end

	def initialize(source:, allowed:, context:, allowed_filters: nil, unknown: UNKNOWN_ERROR, nodes: nil, style: nil)
		@source = source.to_s
		@allowed = allowed.map(&:to_s).reject(&:empty?).uniq
		@allowed_filters = normalise_allowed_filters(allowed_filters)
		@context = context.to_s.empty? ? 'placeholder value' : context.to_s
		@unknown = unknown

		if nodes.nil?
			@nodes, @style = parse_nodes(style)
		else
			@nodes = nodes
			@style = style
		end
	end

	# Returns whether this scalar contains a reference to the named value.
	def include_placeholder?(name)
		@nodes.any? { |node| node.is_a?(PlaceholderNode) && node.name == name.to_s }
	end

	# Returns all referenced placeholder names in source order.
	def placeholder_names
		@nodes.select { |node| node.is_a?(PlaceholderNode) }.map(&:name).uniq
	end

	# Binds available values and preserves any intentionally deferred nodes.
	def bind(values, default_representation:, slugifier: nil)
		value_lookup = normalise_values(values)
		active_slugifier = slugifier || lambda { |value| Jekyll::Utils.slugify(value.to_s) }

		bound_nodes = @nodes.map do |node|
			next node unless node.is_a?(PlaceholderNode)
			next node unless value_lookup.key?(node.name)

			representation = node.filter || default_representation.to_s
			unless FILTERS.include?(representation)
				raise ArgumentError, "Unsupported placeholder representation '#{representation}' in #{@context}."
			end

			resolved = value_lookup[node.name].resolve(
				representation,
				slugifier: active_slugifier,
				name: node.name,
				context: @context
			)
			LiteralNode.new(resolved, splittable: false)
		end

		self.class.new(
			source: @source,
			allowed: @allowed,
			context: @context,
			allowed_filters: @allowed_filters,
			unknown: @unknown,
			nodes: bound_nodes,
			style: @style
		)
	end

	# Resolves values and returns a scalar, optionally rejecting deferred nodes.
	def render(values = {}, default_representation:, slugifier: nil, unresolved: :preserve)
		bound = bind(values, default_representation: default_representation, slugifier: slugifier)
		if unresolved == :error && !bound.placeholder_names.empty?
			raise ArgumentError, "Unresolved placeholder '#{bound.placeholder_names.first}' in #{@context}."
		end

		bound.to_s
	end

	# Splits only source literals. Placeholder results always remain atomic.
	def split(delimiter, limit: nil)
		separator = delimiter.to_s
		return [self] if separator.empty?

		parts = [[]]
		@nodes.each do |node|
			unless node.is_a?(LiteralNode) && node.splittable?
				parts.last << node
				next
			end

			remaining = node.text
			loop do
				can_split = limit.nil? || parts.length < limit
				separator_index = can_split ? remaining.index(separator) : nil
				if separator_index.nil?
					parts.last << LiteralNode.new(remaining) unless remaining.empty?
					break
				end

				prefix = remaining[0...separator_index]
				parts.last << LiteralNode.new(prefix) unless prefix.empty?
				parts << []
				remaining = remaining[(separator_index + separator.length)..-1].to_s
			end
		end

		parts.map do |part_nodes|
			self.class.new(
				source: '',
				allowed: @allowed,
				context: @context,
				allowed_filters: @allowed_filters,
				unknown: @unknown,
				nodes: part_nodes,
				style: @style
			)
		end
	end

	# Serialises unresolved nodes exactly as written and bound values verbatim.
	def to_s
		@nodes.map do |node|
			node.is_a?(LiteralNode) ? node.text : node.source
		end.join
	end

	private

	# Parses canonical expressions first, then greedily lexes legacy tokens in
	# remaining source literals. Unknown canonical expressions stay protected.
	def parse_nodes(_style)
		canonical_nodes, canonical_found = parse_canonical_nodes
		legacy_nodes, legacy_found = parse_legacy_nodes(canonical_nodes)

		if canonical_found && legacy_found
			raise ArgumentError, "Cannot mix canonical '{{ ... }}' and legacy ':placeholder' syntax in #{@context}."
		end

		style = if canonical_found
						:canonical
					elsif legacy_found
						:legacy
					end
		[legacy_nodes, style]
	end

	# Extracts recognised canonical expressions and protects all other Liquid
	# output expressions so the legacy lexer cannot alter their contents.
	def parse_canonical_nodes
		nodes = []
		canonical_found = false
		index = 0

		while index < @source.length
			opening_index = @source.index('{{', index)
			protected_block = next_liquid_protected_block(index)
			if !protected_block.nil? && (opening_index.nil? || protected_block.begin(0) < opening_index)
				append_literal(nodes, @source[index...protected_block.begin(0)])
				block_name = protected_block[1]
				closing_pattern = /\{%-?\s*end#{Regexp.escape(block_name)}\s*-?%\}/
				closing_block = closing_pattern.match(@source, protected_block.end(0))
				block_end = closing_block.nil? ? @source.length : closing_block.end(0)
				nodes << LiteralNode.new(@source[protected_block.begin(0)...block_end], splittable: false)
				index = block_end
				next
			end

			if opening_index.nil?
				append_literal(nodes, @source[index..-1])
				break
			end

			escaped_expression = opening_index.positive? && @source[opening_index - 1] == '\\'
			literal_end = escaped_expression ? opening_index - 1 : opening_index
			append_literal(nodes, @source[index...literal_end])
			closing_index = @source.index('}}', opening_index + 2)
			if closing_index.nil?
				if @unknown == UNKNOWN_ERROR
					raise ArgumentError, "Unclosed canonical placeholder in #{@context}."
				end

				nodes << LiteralNode.new(@source[opening_index..-1], splittable: false)
				break
			end

			source_expression = @source[opening_index..(closing_index + 1)]
			if escaped_expression
				nodes << LiteralNode.new(source_expression, splittable: false)
				index = closing_index + 2
				next
			end

			inner_expression = @source[(opening_index + 2)...closing_index]
			parts = inner_expression.split('|', -1).map(&:strip)
			name = parts.first.to_s

			if @allowed.include?(name)
				validate_canonical_expression!(parts, source_expression)
				filter = parts.length == 2 ? parts.last : nil
				nodes << PlaceholderNode.new(
					name: name,
					filter: filter,
					syntax: :canonical,
					source: source_expression
				)
				canonical_found = true
			elsif @unknown == UNKNOWN_ERROR
				raise ArgumentError, "Unknown placeholder '#{name}' in #{@context}. Allowed placeholders: #{described_allowed_placeholders}."
			else
				nodes << LiteralNode.new(source_expression, splittable: false)
			end

			index = closing_index + 2
		end

		[nodes, canonical_found]
	end

	# Finds Liquid regions whose contents must remain invisible to the plugin.
	def next_liquid_protected_block(index)
		return nil unless @unknown == UNKNOWN_PRESERVE

		/\{%-?\s*(raw|comment)\s*-?%\}/.match(@source, index)
	end

	# Applies the current longest-name-first colon matching rule.
	def parse_legacy_nodes(canonical_nodes)
		sorted_names = @allowed.sort_by { |name| [-name.length, name] }
		return [canonical_nodes, false] if sorted_names.empty?

		legacy_found = false
		nodes = canonical_nodes.flat_map do |node|
			unless node.is_a?(LiteralNode) && node.splittable?
				next [node]
			end

			literal_nodes, found = parse_legacy_literal(node.text, sorted_names)
			legacy_found ||= found
			literal_nodes
		end

		[nodes, legacy_found]
	end

	def parse_legacy_literal(text, sorted_names)
		nodes = []
		literal = String.new
		found = false
		index = 0

		while index < text.length
			if text[index] == '\\' && text[index + 1] == ':'
				name = sorted_names.find { |candidate| text[(index + 2), candidate.length] == candidate }
				unless name.nil?
					literal << ':'
					index += 2
					next
				end
			end

			if text[index] == ':'
				name = sorted_names.find { |candidate| text[(index + 1), candidate.length] == candidate }
				unless name.nil?
					append_literal(nodes, literal)
					literal = String.new
					nodes << PlaceholderNode.new(name: name, filter: nil, syntax: :legacy, source: ":#{name}")
					found = true
					index += name.length + 1
					next
				end
			end

			literal << text[index]
			index += 1
		end

		append_literal(nodes, literal)
		[nodes, found]
	end

	def validate_canonical_expression!(parts, source_expression)
		if parts.first.to_s.empty?
			raise ArgumentError, "Empty canonical placeholder in #{@context}: #{source_expression.inspect}."
		end
		if parts.length > 2
			raise ArgumentError, "Placeholder #{source_expression.inspect} in #{@context} accepts at most one filter."
		end
		return if parts.length == 1

		filter = parts.last.to_s
		unless FILTERS.include?(filter)
			raise ArgumentError, "Unsupported placeholder filter '#{filter}' in #{@context}; expected 'raw' or 'slugify'."
		end

		name = parts.first.to_s
		permitted_filters = permitted_filters_for(name)
		return if permitted_filters.include?(filter)

		if permitted_filters.empty?
			raise ArgumentError, "Placeholder '#{name}' does not accept filters in #{@context}."
		end

		raise ArgumentError, "Placeholder '#{name}' cannot use the '#{filter}' filter in #{@context}; permitted filters: #{permitted_filters.join(', ')}."
	end

	# Normalises optional per-placeholder filter capabilities. Numeric system
	# placeholders remain filterless regardless of caller configuration.
	def normalise_allowed_filters(raw_allowed_filters)
		return {} unless raw_allowed_filters.is_a?(Hash)

		raw_allowed_filters.each_with_object({}) do |(raw_name, raw_filters), filters|
			name = raw_name.to_s
			next if name.empty?

			filters[name] = Array(raw_filters).map(&:to_s).select { |filter| FILTERS.include?(filter) }.uniq
		end
	end

	# Returns filters permitted for one placeholder in this parser context.
	def permitted_filters_for(name)
		return [] if FILTERLESS_PLACEHOLDERS.include?(name)
		return @allowed_filters[name] if @allowed_filters.key?(name)

		FILTERS
	end

	def append_literal(nodes, text)
		return if text.nil? || text.empty?

		nodes << LiteralNode.new(text)
	end

	def normalise_values(values)
		return {} unless values.is_a?(Hash)

		values.each_with_object({}) do |(raw_name, raw_value), memo|
			name = raw_name.to_s
			next if name.empty?

			memo[name] = raw_value.is_a?(Value) ? raw_value : Value.new(raw: raw_value)
		end
	end

	def described_allowed_placeholders
		return '(none)' if @allowed.empty?

		@allowed.sort.join(', ')
	end
end

end
end
end
end
