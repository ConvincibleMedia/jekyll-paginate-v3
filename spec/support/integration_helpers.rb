# frozen_string_literal: true

module IntegrationHelpers
	# Normalises URL strings for comparisons so trailing slash form does not
	# affect expectation outcomes (`/a/b` and `/a/b/` are equivalent).
	def normalise_url_for_match(url)
		value = url.to_s.strip
		return value if value.empty?

		value = "/#{value}" unless value.start_with?('/')
		return '/' if value == '/'

		value.sub(%r{/\z}, '')
	end

	# Builds the baseline site definition used by all integration examples.
	#
	# The returned blueprint keeps default config and core layouts in one reusable
	# object so each spec can override only what it needs via `jekyll_build`.
	def default_site
		listing_layout_markup = <<~HTML
			<!doctype html>
			<html>
				<body>
					<main id="content">
						{{ content }}
					</main>
					{% if paginator %}
						<p id="current-page">{{ paginator.current.num | default: paginator.page }}</p>
						<p id="total-pages">{{ paginator.total_indexes | default: paginator.total_pages }}</p>
						<ul id="items">
							{% for item in paginator.items %}
								<li>{{ item.title }}</li>
							{% endfor %}
						</ul>
						<ul id="alias-items">
							{% if paginator.posts %}
								{% for item in paginator.posts %}
									<li>{{ item.title }}</li>
								{% endfor %}
							{% endif %}
						</ul>
						<ol id="trail">
							{% if paginator.trail %}
								{% for entry in paginator.trail %}
									<li>{{ entry.num }}|{% if entry.page %}{{ entry.page.url }}{% endif %}|{{ entry.current }}|{{ entry.distance }}</li>
								{% endfor %}
							{% elsif paginator.page_trail %}
								{% for entry in paginator.page_trail %}
									<li>{{ entry.num }}|{{ entry.path }}|{{ entry.title }}|</li>
								{% endfor %}
							{% endif %}
						</ol>
					{% endif %}
				</body>
			</html>
		HTML

		jekyll_blueprint(
			config: {
				'title' => 'Spec Site',
				'url' => 'https://example.test',
				'plugins' => ['jekyll-paginate-v3'],
				'collections' => {
					'products' => { 'output' => true },
					'guides' => { 'output' => true },
					'notes' => { 'output' => true }
				},
				'pagination' => {
					'enabled' => true
				}
			},
			files: jekyll_files do
				folder '_layouts' do
					file 'default.html' do
						contents(listing_layout_markup)
					end

					file 'listing.html' do
						frontmatter('layout' => 'default')
						contents('{{ content }}')
					end

					file 'post.html' do
						frontmatter('layout' => 'default')
						contents('<article>{{ content }}</article>')
					end

					file 'autopage_tags.html' do
						frontmatter('layout' => 'default')
						contents('{{ content }}')
					end

					file 'autopage_category.html' do
						frontmatter('layout' => 'default')
						contents('{{ content }}')
					end

					file 'autopage_collection.html' do
						frontmatter('layout' => 'default')
						contents('{{ content }}')
					end
				end
			end
		)
	end

	# Returns canonical frontmatter for a pagination template.
	#
	# Use with the harness file DSL:
	# `frontmatter(pagination_template_frontmatter(...))`
	def pagination_template_frontmatter(overrides = {})
		defaults = {
			'layout' => 'listing',
			'title' => 'Listing',
			'pagination' => {
				'enabled' => true
			}
		}
		jekyll_merge(defaults, overrides)
	end

	# Produces a hash of post file paths and document bodies.
	#
	# The optional block receives the 1-based index and can return additional
	# frontmatter overrides for each post.
	def post_files(total_count, start_day: 1)
		jekyll_files do
			folder '_posts' do
				total_count.times do |offset|
					number = offset + 1
					day = start_day + offset
					slug = format('post-%02d', number)
					filename = "2026-01-#{format('%02d', day)}-#{slug}.md"

					frontmatter_data = {
						'layout' => 'post',
						'title' => "Post #{format('%02d', number)}",
						'date' => "2026-01-#{format('%02d', day)} 12:00:00 +0000"
					}
					frontmatter_data = frontmatter_data.merge((yield(number) || {})) if block_given?

					file filename do
						frontmatter(frontmatter_data)
						contents("Post body #{number}")
					end
				end
			end
		end
	end

	# Builds one collection document as a nested files hash.
	def collection_document(collection_label, filename, frontmatter_data = {}, body = '')
		jekyll_files do
			folder "_#{collection_label}" do
				file filename do
					frontmatter(frontmatter_data)
					contents(body)
				end
			end
		end
	end

	# Finds generated pagination pages in site.pages.
	def generated_pagination_pages(site)
		site.pages.select { |item| item.data.dig('pagination', 'index') }
	end

	# Finds generated pagination documents in a specific collection.
	def generated_pagination_documents(site, collection_label)
		collection = site.collections.fetch(collection_label)
		collection.docs.select { |item| item.data.dig('pagination', 'index') }
	end

	# Finds a page by URL.
	def page_by_url(site, url)
		target = normalise_url_for_match(url)
		site.pages.find { |page| normalise_url_for_match(page.url) == target }
	end

	# Finds a collection document by URL.
	def document_by_url(site, collection_label, url)
		target = normalise_url_for_match(url)
		site.collections.fetch(collection_label).docs.find { |document| normalise_url_for_match(document.url) == target }
	end

	# Returns paginator payload as a Liquid-style hash.
	def paginator_payload(item)
		payload = item.data.fetch('paginator')
		return payload.to_h if payload.respond_to?(:to_h)
		return payload.to_liquid if payload.respond_to?(:to_liquid)

		payload
	end

	# Extracts one canonical paginator index number.
	def paginator_index_number(item)
		payload = paginator_payload(item)
		current = payload['current']

		if current.respond_to?(:num)
			return current.num
		end

		if current.is_a?(Hash)
			return current.fetch('num')
		end

		payload.fetch('page')
	end

	# Extracts a paginator neighbour/trail reference number.
	def paginator_reference_number(item, key)
		reference = paginator_payload(item)[key]
		return nil if reference.nil?

		if reference.respond_to?(:num)
			return reference.num
		end

		if reference.is_a?(Hash)
			return reference['num']
		end

		reference
	end

	# Extracts URL from one paginator reference object.
	def paginator_reference_url(item, key)
		reference = paginator_payload(item)[key]
		return nil if reference.nil?

		page_object = if reference.respond_to?(:page)
										reference.page
									elsif reference.is_a?(Hash)
										reference['page']
									end

		return nil if page_object.nil?
		return nil unless page_object.respond_to?(:url)

		page_object.url
	end

	# Extracts paginator item titles from a generated page/document.
	def paginator_item_titles(item, key: 'items')
		payload = paginator_payload(item)
		items = payload.fetch(key)
		items.map { |entry| entry.data.fetch('title') }
	end

	# Extracts trail page numbers from paginator payload.
	def paginator_trail_numbers(item)
		payload = paginator_payload(item)
		entries = payload.key?('trail') ? payload.fetch('trail') : payload.fetch('page_trail')
		entries ||= []

		entries.map do |entry|
			if entry.respond_to?(:num)
				entry.num
			else
				entry['num']
			end
		end
	end

	# Extracts grouped-set payload from paginator data.
	def paginator_group_payload(item)
		payload = paginator_payload(item)
		group = payload['group']
		return nil if group.nil?
		return group.to_h if group.respond_to?(:to_h)

		group
	end

	# Extracts grouped-set payload array from paginator data.
	def paginator_groups_payload(item)
		payload = paginator_payload(item)
		groups = payload['groups']
		return [] if groups.nil?

		groups.map do |group|
			group.respond_to?(:to_h) ? group.to_h : group
		end
	end

	# Extracts one grouped-set reference hash by key.
	def paginator_group_reference(item, key)
		group_payload = paginator_group_payload(item)
		return nil if group_payload.nil?

		reference = group_payload[key]
		return nil if reference.nil?
		return reference.to_h if reference.respond_to?(:to_h)

		reference
	end
end
