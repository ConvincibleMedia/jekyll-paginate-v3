# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Backwards-compatible aliases so grouped payload classes remain
# reachable under `Paginator::...` as expected by callers.
class Paginator
  GroupPayload = Pagination::GroupPayload unless const_defined?(:GroupPayload, false)
  GroupReference = Pagination::GroupReference unless const_defined?(:GroupReference, false)
end

end
end
end
end
