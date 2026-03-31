# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3

# URL and path normalisation helpers.
#
# Used by paginator/page generation code to keep output paths stable.
module Utils
	
	# Removes one leading slash from a path-like string.
	def self.remove_leading_slash(path)
		string_path = path.to_s
		string_path.start_with?('/') ? string_path[1..-1] : string_path
	end

	# Ensures a path-like string has a leading slash.
	def self.ensure_leading_slash(path)
		string_path = path.to_s
		string_path.start_with?('/') ? string_path : "/#{string_path}"
	end

	# Ensures a path-like string has a trailing slash.
	def self.ensure_trailing_slash(path)
		string_path = path.to_s
		string_path.end_with?('/') ? string_path : "#{string_path}/"
	end

	# Ensures a filename extension has a leading dot.
	def self.ensure_leading_dot(extension)
		string_extension = extension.to_s
		return '' if string_extension.empty?

		string_extension.start_with?('.') ? string_extension : ".#{string_extension}"
	end

	# Normalises a full path by appending a default filename and extension when needed.
	def self.ensure_full_path(path, default_index_name, default_extension)
		url = path.to_s
		extension = ensure_leading_dot(default_extension)
		index_name = default_index_name.to_s

		if url.end_with?('/')
			return "#{url}#{index_name}#{extension}"
		end

		return "#{url}#{extension}" if File.extname(url).empty?

		url
	end

	# Builds one deterministic synthetic source path for in-memory pages
	# and documents. Filenames remain readable for debugging while a hash
	# suffix preserves practical uniqueness across templates and variants.
	def self.build_synthetic_source_path(site:, extension:, signature:, collection: nil, source_path: nil, source_stem: nil, role:, page_number: nil)
		directory = collection.nil? ? site.source : File.join(site.source, collection.relative_directory)
		File.join(
			directory,
			build_synthetic_filename(
				extension: extension,
				signature: signature,
				source_path: source_path,
				source_stem: source_stem,
				role: role,
				page_number: page_number
			)
		)
	end

	# Builds one readable synthetic filename from source identity plus a
	# deterministic safety suffix.
	def self.build_synthetic_filename(extension:, signature:, source_path: nil, source_stem: nil, role:, page_number: nil)
		stem = derive_synthetic_source_stem(source_path: source_path, source_stem: source_stem, fallback: role)
		filename_segments = [stem, role.to_s.strip]
		filename_segments << page_number.to_i.to_s unless page_number.nil?
		filename_segments << Digest::MD5.hexdigest(canonical_signature(signature).inspect)
		"#{filename_segments.reject(&:empty?).join('-')}#{ensure_leading_dot(extension)}"
	end

	# Derives one human-readable synthetic stem from an original source
	# path or fallback label.
	def self.derive_synthetic_source_stem(source_path: nil, source_stem: nil, fallback: 'generated')
		candidate = extract_source_filename_stem(source_path)
		candidate = source_stem.to_s if candidate.empty?
		candidate = fallback.to_s if candidate.to_s.strip.empty?
		sanitise_filename_component(candidate, fallback: fallback)
	end

	# Derives one readable stem from frontmatter when no real source path
	# exists, preferring permalink and then title.
	def self.derive_synthetic_source_stem_from_frontmatter(frontmatter, fallback: 'generated')
		frontmatter_hash = safe_hash(frontmatter)
		permalink_stem = extract_permalink_stem(frontmatter_hash['permalink'])
		return derive_synthetic_source_stem(source_stem: permalink_stem, fallback: fallback) unless permalink_stem.empty?

		derive_synthetic_source_stem(source_stem: frontmatter_hash['title'], fallback: fallback)
	end

	# Extracts one source-style stem from a real path-like value.
	def self.extract_source_filename_stem(source_path)
		path = source_path.to_s
		return '' if path.strip.empty?

		File.basename(path, File.extname(path))
	end

	# Extracts one final path segment from a permalink-like value.
	def self.extract_permalink_stem(permalink)
		path = permalink.to_s.strip
		return '' if path.empty?

		segments = path.split('/').reject(&:empty?)
		return '' if segments.empty?

		File.basename(segments.last, File.extname(segments.last))
	end

	# Sanitises one filename component while preserving source readability
	# where the original stem is already filesystem-safe.
	def self.sanitise_filename_component(value, fallback: 'generated')
		component = value.to_s.strip
		component = component.gsub(%r{[\\/]}, '-')
		component = component.gsub(/[<>:"|?*\x00-\x1f]/, '-')
		component = component.gsub(/^-+/, '')
		component = component.gsub(/[. ]+$/, '')
		component = fallback.to_s if component.empty?
		component
	end

	# Canonicalises nested signature data so hashes with identical meaning
	# yield the same suffix regardless of insertion order.
	def self.canonical_signature(value)
		case value
		when Hash
			value.each_with_object({}) do |(key, nested_value), canonical|
				canonical[key.to_s] = canonical_signature(nested_value)
			end.sort_by { |key, _| key }.to_h
		when Array
			value.map { |entry| canonical_signature(entry) }
		else
			value
		end
	end
end

end
end
end
