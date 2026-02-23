# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Query
        # Parses and evaluates the shared "search" format used across v3.
        #
        # Supported input forms:
        # - String: `pages`, `posts`, `all`, `everything`
        # - Hash: `{ pages: '*' }`, `{ posts: ['news/*', 'blog/*'] }`
        # - Array: combination of string/hash entries
        # - Delimited String: `pages, posts` (delimiter is configurable)
        #
        # Used by Pagination::Model and Templates::Builder to resolve configured
        # sources into concrete site items.
        class Parser
          CANONICAL_TYPES = %w[pages all everything].freeze

          # Parses a search definition into an array of normalised entries.
          #
          # Each entry has shape: `{ 'type' => <String>, 'paths' => <Array|nil> }`
          # where `paths == nil` means no path filtering.
          def self.parse(raw_search, keywords, split_delimiter: ',')
            parsed_entries = []
            parse_into(raw_search, keywords, parsed_entries, split_delimiter)
            parsed_entries
          end

          # Returns the first parsed search type if present.
          def self.first_type(raw_search, keywords, split_delimiter: ',')
            parse(raw_search, keywords, split_delimiter: split_delimiter).first&.fetch('type', nil)
          end

          # Matches a site-relative path against optional search path filters.
          def self.path_allowed?(relative_path, normalised_paths)
            return true if normalised_paths.nil? || normalised_paths.empty?

            clean_path = Utils.remove_leading_slash(relative_path.to_s)
            normalised_paths.any? do |pattern|
              if pattern.include?('*')
                File.fnmatch?(pattern, clean_path, File::FNM_PATHNAME)
              else
                clean_path.start_with?(Utils.remove_leading_slash(pattern))
              end
            end
          end

          # Normalises keyword mapping so callers can safely pass partial config.
          def self.normalise_keywords(raw_keywords)
            defaults = {
              'pages' => 'pages',
              'all' => 'all',
              'everything' => 'everything'
            }

            defaults.merge(Utils.safe_hash(raw_keywords))
          end

          class << self
            private

            # Normalises each supported input type into parsed entry hashes.
            def parse_into(raw_search, keywords, parsed_entries, split_delimiter)
              return if raw_search.nil?

              normalised_keywords = normalise_keywords(keywords)

              if raw_search.is_a?(Array)
                raw_search.each { |entry| parse_into(entry, normalised_keywords, parsed_entries, split_delimiter) }
                return
              end

              if raw_search.is_a?(Hash)
                Utils.safe_hash(raw_search).each do |type, raw_paths|
                  parsed_entries << {
                    'type' => canonical_type(type, normalised_keywords),
                    'paths' => normalise_paths(raw_paths, split_delimiter)
                  }
                end
                return
              end

              parse_string_entry(raw_search, normalised_keywords, parsed_entries, split_delimiter)
            end

            # Handles scalar string entries, including delimiter-defined shorthand.
            def parse_string_entry(raw_search, keywords, parsed_entries, split_delimiter)
              value = raw_search.to_s.strip
              return if value.empty?

              Utils.delimited_array(value, delimiter: split_delimiter).each do |entry|
                entry_value = entry.to_s.strip
                next if entry_value.empty?

                parsed_entries << {
                  'type' => canonical_type(entry_value, keywords),
                  'paths' => nil
                }
              end
            end

            # Maps configurable keyword aliases (`pages`, `all`, `everything`)
            # to their canonical internal type.
            def canonical_type(type, keywords)
              string_type = type.to_s.strip
              return 'pages' if string_type == 'pages' || string_type == keywords['pages']
              return 'all' if string_type == 'all' || string_type == keywords['all']
              return 'everything' if string_type == 'everything' || string_type == keywords['everything']

              string_type
            end

            # Normalises path filters and treats `*` as "no filtering".
            def normalise_paths(raw_paths, split_delimiter)
              paths = []

              if raw_paths.is_a?(Array)
                raw_paths.each do |entry|
                  paths.concat(Utils.delimited_array(entry, delimiter: split_delimiter))
                end
              else
                paths = Utils.delimited_array(raw_paths, delimiter: split_delimiter)
              end

              paths = paths.map { |path| Utils.remove_leading_slash(path.to_s.strip) }.reject(&:empty?).uniq
              return nil if paths.empty? || paths.include?('*')

              paths
            end
          end
        end
      end
    end
  end
end
