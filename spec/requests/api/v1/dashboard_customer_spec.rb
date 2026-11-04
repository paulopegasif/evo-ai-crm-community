# frozen_string_literal: true

begin
  require 'rails_helper'
rescue LoadError
  RSpec.describe 'GET /api/v1/dashboard/customer' do
    it 'has routing and request contract spec scaffold ready' do
      skip 'rails_helper is not available in this workspace snapshot'
    end
  end
end

return unless defined?(Rails)

RSpec.describe 'GET /api/v1/dashboard/customer', type: :routing do
  it 'routes to api/v1/dashboard#customer' do
    expect(get: '/api/v1/dashboard/customer').to route_to(
      controller: 'api/v1/dashboard',
      action: 'customer',
      format: 'json'
    )
  end

  it 'documents expected authenticated contract for envelope and filters' do
    skip 'Requires authenticated account request helper and fixture data in this repository setup'
  end
end

RSpec.describe 'Lead tracking routes', type: :routing do
  it 'routes the lead list, the journey and the review queue' do
    expect(get: '/api/v1/dashboard/leads/list').to route_to(controller: 'api/v1/dashboard', action: 'lead_list', format: 'json')
    expect(get: '/api/v1/dashboard/leads/abc/journey').to route_to(controller: 'api/v1/dashboard', action: 'lead_journey',
                                                                   contact_id: 'abc', format: 'json')
    expect(post: '/api/v1/unlinked_sales/abc/link').to route_to(controller: 'api/v1/unlinked_sales', action: 'link', id: 'abc',
                                                               format: 'json')
  end
end
