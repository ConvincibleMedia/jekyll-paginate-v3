# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Pagination::Paginator do
  it 'raises an error when current page exceeds total pages' do
    expect do
      described_class.new(
        per_page: 10,
        first_page_url: '/blog/',
        paginated_page_url: '/blog/page/:num/',
        items: [1, 2, 3],
        current_page: 3,
        total_pages: 2,
        index_name: 'index',
        extension: 'html',
        item_keyword: 'items'
      )
    end.to raise_error(ArgumentError, /cannot be greater than total pages/)
  end

  it 'builds consistent page paths and alias keys in liquid payloads' do
    paginator = described_class.new(
      per_page: 2,
      first_page_url: '/articles/',
      paginated_page_url: '/articles/page/:num/',
      items: [1, 2, 3, 4, 5],
      current_page: 2,
      total_pages: 3,
      index_name: 'index',
      extension: 'html',
      item_keyword: 'posts'
    )
    payload = paginator.to_liquid

    expect(paginator.items).to eq([3, 4])
    expect(payload['page_path']).to eq('/articles/page/2/index.html')
    expect(payload['previous_page_path']).to eq('/articles/index.html')
    expect(payload['next_page_path']).to eq('/articles/page/3/index.html')
    expect(payload['first_page_path']).to eq('/articles/index.html')
    expect(payload['last_page_path']).to eq('/articles/page/3/index.html')
    expect(payload['posts']).to eq([3, 4])
    expect(payload['total_posts']).to eq(5)
  end

  it 'falls back to items when the configured alias keyword is blank' do
    paginator = described_class.new(
      per_page: 5,
      first_page_url: '/',
      paginated_page_url: '/page/:num/',
      items: [1],
      current_page: 1,
      total_pages: 1,
      index_name: 'index',
      extension: 'html',
      item_keyword: '   '
    )
    payload = paginator.to_liquid

    expect(payload['items']).to eq([1])
    expect(payload['total_items']).to eq(1)
  end
end
