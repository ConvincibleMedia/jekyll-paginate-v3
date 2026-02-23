# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Pagination
        # Core pagination orchestration model.
        #
        # Responsibilities:
        # - discover pagination templates
        # - generate configured templates (`pagination.templates.generate`)
        # - resolve and filter/sort items per template
        # - emit paginated index pages/documents
        #
        # Used by Generators::PaginationGenerator as the main runtime
        # coordinator for the pagination pipeline.
        class Model
          def initialize(site:, site_config:, log_lambda:, add_item_lambda:, remove_item_lambda:)
            @site = site
            @site_config = site_config
            @log_lambda = log_lambda
            @add_item_lambda = add_item_lambda
            @remove_item_lambda = remove_item_lambda
            @nested_separator = site_config['nested_key_separator']
            @equivalents = site_config['equivalents']
            @item_keyword = site_config.dig('keywords', 'items') || 'items'
          end

          # Runs the full pagination pipeline for the current site build.
          def run
            @log_lambda.call("Pagination pipeline start: compatibility=#{@site_config['compatibility'] || 'none'} templates.location=#{@site_config.dig('templates', 'location')} generate.count=#{@site_config.dig('templates', 'generate')&.length || 0}", 'debug')

            generated_template_count = build_generated_templates
            @log_lambda.call("Generated #{generated_template_count} template(s).", 'debug')

            templates = discover_templates
            if templates.empty?
              @log_lambda.call('Enabled, but no pagination templates were discovered.', 'warn')
              return 0
            end

            @log_lambda.call("Discovered #{templates.length} pagination template(s).", 'debug')
            processed = 0
            templates.each do |template|
              next unless template.data['pagination'].is_a?(Hash)

              template_config = Config::Normaliser.normalise_template_config(@site_config, template.data['pagination'])
              next unless template_config['enabled']

              @log_lambda.call("Paginating template '#{Utils.relative_item_path(template)}' with items=#{template_config['items']} filters=#{template_config['filters']}.", 'debug')
              paginate_template(template, template_config)
              processed += 1
            end

            @log_lambda.call("Pagination pipeline complete: processed #{processed} template(s).", 'debug')
            processed
          end

          private

          # Builds synthetic pagination templates from `templates.generate`.
          def build_generated_templates
            builder = Templates::Builder.new(
              site: @site,
              site_config: @site_config,
              add_item_lambda: @add_item_lambda,
              resolve_items_lambda: method(:resolve_items),
              log_lambda: @log_lambda
            )
            builder.build
          end

          # Discovers all pages/documents configured as pagination templates.
          def discover_templates
            candidates = resolve_items(
              @site_config.dig('templates', 'location'),
              include_templates: true,
              include_generated_indexes: true,
              include_hidden: true
            )

            templates = candidates.select { |item| explicit_template?(item) }
            generated_templates = (@site.pages + all_collection_documents).select do |item|
              next false unless item.respond_to?(:data)
              next false unless item.data.is_a?(Hash)
              next false unless item.data.dig('paginate_v3', 'generated_template')

              explicit_template?(item)
            end
            templates.concat(generated_templates)
            templates.uniq!
            apply_implicit_v1_template_fallback(candidates, templates)
          end

          # Identifies a hand-authored pagination template from frontmatter.
          def explicit_template?(item)
            return false unless item.respond_to?(:data)
            return false unless item.data.is_a?(Hash)

            pagination = Utils.safe_hash(item.data['pagination'])
            return false unless pagination['enabled']

            item.data['pagination'] = pagination
            item.data['pagination']['template'] = true
            true
          end

          # Provides an implicit v1 migration path when old `paginate` config
          # is present but no page has `pagination.enabled: true`.
          #
          # This keeps v1 compatibility focused on config migration while still
          # allowing the shared v3 pipeline to process the intended template.
          def apply_implicit_v1_template_fallback(candidates, templates)
            return templates unless templates.empty?
            return templates unless @site_config['compatibility'] == 'v1'
            return templates unless legacy_v1_site_config_present?

            template = legacy_v1_template_candidate(candidates)
            return templates if template.nil?

            template.data['pagination'] = Utils.safe_hash(template.data['pagination'])
            template.data['pagination']['enabled'] = true
            template.data['pagination']['template'] = true

            @log_lambda.call("v1 compatibility: no explicit templates found; selected implicit template '#{Utils.relative_item_path(template)}'.", 'debug')
            [template]
          end

          # Detects whether the site includes the legacy v1 top-level config key.
          def legacy_v1_site_config_present?
            !@site.config['paginate'].nil?
          end

          # Selects the legacy v1 index page candidate as an implicit template.
          # The deepest matching `index.html` under the configured paginate path
          # hierarchy is preferred.
          def legacy_v1_template_candidate(items)
            source_root = File.expand_path(@site.config['source'].to_s)
            paginate_path = @site_config['permalink']

            items.select { |item| legacy_v1_pagination_candidate?(source_root, paginate_path, item) }.sort_by { |item| -item.path.to_s.size }.first
          end

          # Mirrors v1 template candidate detection rules for migration fallback.
          def legacy_v1_pagination_candidate?(source_root, paginate_path, item)
            return false unless item.respond_to?(:name)
            return false unless item.respond_to?(:path)
            return false if item.respond_to?(:collection) && !item.collection.nil?
            return false if Utils.generated_index?(item)
            return false unless item.name.to_s == 'index.html'

            page_dir = File.dirname(File.expand_path(Utils.remove_leading_slash(item.path), source_root))
            full_paginate_path = File.expand_path(Utils.remove_leading_slash(paginate_path), source_root)
            legacy_v1_in_hierarchy?(source_root, page_dir, File.dirname(full_paginate_path))
          end

          # Traverses parent directories to determine whether the page directory
          # is inside the legacy paginate path hierarchy.
          def legacy_v1_in_hierarchy?(source_root, page_dir, paginate_dir)
            source_parent = File.dirname(File.expand_path(source_root))
            current_dir = paginate_dir

            loop do
              return false if current_dir == File.dirname(current_dir)
              return false if current_dir == source_parent
              return true if page_dir == current_dir

              current_dir = File.dirname(current_dir)
            end
          end

          # Resolves the shared search format into concrete site items and then
          # applies generic inclusion/exclusion flags.
          def resolve_items(raw_search, include_templates: false, include_generated_indexes: false, include_hidden: false)
            entries = Query::Parser.parse(raw_search, @site_config['keywords'], split_delimiter: @site_config['split'])
            return [] if entries.empty?

            @log_lambda.call("Resolving items from search=#{raw_search.inspect} (entries=#{entries.length}, include_templates=#{include_templates}, include_generated_indexes=#{include_generated_indexes}, include_hidden=#{include_hidden}).", 'debug')
            resolved = []
            entries.each do |entry|
              resolved.concat(resolve_entry(entry))
            end

            resolved.uniq!
            resolved.sort_by! { |item| Utils.relative_item_path(item) }
            @log_lambda.call("Resolved #{resolved.length} unique item(s) before exclusion filters.", 'debug')

            resolved.select! { |item| !Utils.generated_index?(item) } unless include_generated_indexes
            resolved.select! { |item| !Utils.pagination_template?(item) } unless include_templates
            resolved.select! { |item| !item['hidden'] } unless include_hidden

            @log_lambda.call("Resolved #{resolved.length} item(s) after exclusion filters.", 'debug')
            resolved
          end

          # Resolves one parsed search entry (`pages`, collection label, etc).
          def resolve_entry(entry)
            type = entry['type']
            paths = entry['paths']

            source_items = case type
                           when 'pages'
                             @site.pages
                           when 'all'
                             all_collection_documents
                           when 'everything'
                             @site.pages + all_collection_documents
                           else
                             @site.collections[type]&.docs || []
                           end

            @log_lambda.call("Resolving entry type='#{type}' paths=#{paths.inspect} from #{source_items.length} source item(s).", 'debug')
            source_items.select do |item|
              Query::Parser.path_allowed?(Utils.relative_item_path(item), paths)
            end
          end

          def all_collection_documents
            @site.collections.values.flat_map(&:docs)
          end

          # Applies item resolution, filtering, sorting, offset and limit before
          # generating concrete pages.
          def paginate_template(template, config)
            all_items = resolve_items(config['items'])
            @log_lambda.call("Template '#{Utils.relative_item_path(template)}': resolved #{all_items.length} candidate item(s).", 'debug')
            filtered_items = Query::Filter.filter_items(
              all_items,
              config['filters'],
              nested_separator: @nested_separator,
              equivalents: @equivalents,
              split_delimiter: config['split'],
              now_keyword: config.dig('keywords', 'now'),
              log_lambda: @log_lambda
            )
            @log_lambda.call("Template '#{Utils.relative_item_path(template)}': #{filtered_items.length} item(s) after filters=#{config['filters']}.", 'debug')

            sorted_items = Query::Sorter.apply(
              filtered_items,
              config['sort'],
              nested_separator: @nested_separator,
              equivalents: @equivalents,
              split_delimiter: config['split']
            )
            @log_lambda.call("Template '#{Utils.relative_item_path(template)}': sorted #{sorted_items.length} item(s) by #{config['sort']} before offset.", 'debug')

            offset = [config['offset'].to_i, 0].max
            sorted_items = sorted_items.drop(offset)
            @log_lambda.call("Template '#{Utils.relative_item_path(template)}': #{sorted_items.length} item(s) after offset=#{offset}.", 'debug')

            total_pages = Utils.calculate_number_of_pages(sorted_items, config['per_page'])
            total_pages = 1 if total_pages.zero?

            if config['limit'].to_i > 0
              total_pages = [total_pages, config['limit'].to_i].min
            end

            @log_lambda.call("Template '#{Utils.relative_item_path(template)}': generating #{total_pages} page(s) with per_page=#{config['per_page']} limit=#{config['limit']}.", 'debug')
            emit_paginated_pages(template, config, sorted_items, total_pages)
          end

          # Replaces a template with one synthetic page/document per page number.
          def emit_paginated_pages(template, config, items, total_pages)
            @remove_item_lambda.call(template)

            new_pages = []
            index_name = config['indexpage'].to_s
            extension = Utils.ensure_leading_dot(config['extension'])
            index_file = "#{index_name}#{extension}"

            first_page_url = template_first_page_url(template)
            paginated_page_url = if config['compatibility'] == 'v1' && legacy_v1_site_config_present? && !@site.config['paginate_path'].nil?
                                   Utils.ensure_leading_slash(config['permalink'].to_s)
                                 else
                                   join_url(first_page_url, config['permalink'])
                                 end

            (1..total_pages).each do |current_page|
              generated = if template.respond_to?(:collection)
                            Pages::Document.new(template, current_page, total_pages, index_file)
                          else
                            Pages::Page.new(template, current_page, total_pages, index_file)
                          end

              generated.pager = Paginator.new(
                per_page: config['per_page'],
                first_page_url: first_page_url,
                paginated_page_url: paginated_page_url,
                items: items,
                current_page: current_page,
                total_pages: total_pages,
                index_name: index_name,
                extension: extension,
                item_keyword: @item_keyword
              )

              generated.set_url(synthetic_page_url(generated.pager.page_path, index_name, extension))
              generated.data['pagination'] = Utils.safe_hash(generated.data['pagination'])
              generated.data['pagination'].delete('template')
              generated.data['pagination']['index'] = true

              # Only mark emitted indexes as generated when their source
              # template came from the template-generation pipeline.
              if template.data.dig('paginate_v3', 'generated_template')
                generated.data['pagination']['generated'] = true
              else
                generated.data['pagination'].delete('generated')
              end
              generated.data['paginator'] = generated.pager.to_liquid
              generated.data.delete('paginate_v3')
              generated.data['autogen'] = 'jekyll-paginate-v2' if config['compatibility'] == 'v2'

              if template.data['permalink']
                generated.data['permalink'] = generated.pager.page_path
              end

              base_title = template.data['title'] || @site.config['title']
              if current_page > 1
                generated.data['title'] = Utils.format_page_title(config['title'], base_title, current_page, total_pages)
              else
                generated.data['title'] = base_title
              end

              @add_item_lambda.call(generated)
              @log_lambda.call("Emitted pagination page #{current_page}/#{total_pages} at '#{generated.url}' for template '#{Utils.relative_item_path(template)}'.", 'debug')
              new_pages << generated
            end

            apply_page_trail(new_pages, config)
          end

          # Attaches a compact neighbourhood of page links around each generated
          # page when `trail.before/after` is configured.
          def apply_page_trail(generated_pages, config)
            return if generated_pages.length <= 1
            return unless config['trail'].is_a?(Hash)

            before = [config['trail']['before'].to_i, 0].max
            after = [config['trail']['after'].to_i, 0].max
            return if before.zero? && after.zero?

            trail_size = before + after + 1
            @log_lambda.call("Applying page trail with before=#{before} after=#{after} size=#{trail_size} across #{generated_pages.length} generated page(s).", 'debug')

            generated_pages.each do |page|
              range_start = [page.pager.page - before - 1, 0].max
              range_end = [range_start + trail_size, generated_pages.length].min

              if range_end - range_start < trail_size
                range_start = [range_start - (trail_size - (range_end - range_start)), 0].max
              end

              page.pager.page_trail = generated_pages[range_start...range_end].each_with_index.map do |trail_page, index|
                PageTrail.new(range_start + index + 1, trail_page.url, trail_page.data['title'])
              end
              page.data['paginator'] = page.pager.to_liquid
              @log_lambda.call("Assigned trail to page #{page.pager.page}: range_start=#{range_start + 1} range_end=#{range_end}.", 'debug')
            end
          end

          # Determines the canonical URL for the first pagination page of a template.
          def template_first_page_url(template)
            permalink = template.data['permalink']
            unless permalink.nil? || permalink.to_s.strip.empty?
              return Utils.ensure_leading_slash(permalink.to_s)
            end

            if template.respond_to?(:url) && !template.url.to_s.strip.empty?
              return Utils.ensure_leading_slash(template.url.to_s)
            end

            if template.respond_to?(:cleaned_relative_path)
              return "/#{template.cleaned_relative_path}/"
            end

            "/#{Utils.remove_leading_slash(File.join(template.dir.to_s, template.basename.to_s))}/"
          end

          # Joins a base URL and relative suffix while preserving one leading slash.
          def join_url(base_url, suffix)
            joined = "#{Utils.ensure_trailing_slash(base_url)}#{Utils.remove_leading_slash(suffix.to_s)}"
            Utils.ensure_leading_slash(joined)
          end

          # Converts full output file paths into clean route-style URLs used by
          # Jekyll pages/documents.
          def synthetic_page_url(page_path, index_name, extension)
            full_index_name = "#{index_name}#{extension}"
            if !index_name.to_s.empty? && page_path.end_with?(full_index_name)
              trimmed = page_path[0...-full_index_name.length]
              return Utils.ensure_trailing_slash(trimmed)
            end

            if !extension.to_s.empty? && page_path.end_with?(extension)
              return page_path[0...-extension.length]
            end

            page_path
          end
        end
      end
    end
  end
end
