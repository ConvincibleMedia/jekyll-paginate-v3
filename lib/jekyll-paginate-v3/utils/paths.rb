# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # URL and path normalisation helpers.
        #
        # Used by paginator/page generation code to keep output paths stable.

        # Removes one leading slash from a path-like string.
        def self.remove_leading_slash(path)
          string_path = path.to_s
          string_path.start_with?('/') ? string_path[1..] : string_path
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
      end
    end
  end
end
