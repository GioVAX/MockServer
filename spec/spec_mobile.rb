require_relative 'spec_helper'

# Test class for mobile endpoints
class SpecMobile < Minitest::Spec
  describe 'Mobile' do
    before(:all) do
      MockBackend::API.reload_endpoints(nil, file: 'mobile_endpoints')
    end

    after(:all) do
      MockBackend::Boot.exit
    end

    it 'should run mock server in default url' do
      MockBackend::Bind.url.must_equal('http://127.0.0.1:9292')
    end

    it 'should respond to root endpoint' do
      response = SpecUtils::Utils.get('/')
      response.code.must_equal(200)
      response.body.wont_be_nil
    end

    it 'should return 404 for unknown endpoints' do
      SpecUtils::Utils.get('foo/foo').code.must_equal(404)
    end

    it 'should return 200 status code and body for known GET endpoints' do
      endpoints = %w[collector/details collector/segmentation collector/offers collector/offers/123abc/swipeInfo
                     collectors/19693730018/status rewards/ROM123456 collector/statement/mini collector/vouchers
                     api/brands api/brands/apple collector/clickout-url]

      # TODO
      # collector/preferences
      # api/categories

      endpoints.each do |endpoint|
        response = SpecUtils::Utils.get(endpoint)
        response.code.must_equal(200)
        response.body.wont_be_nil
      end
    end

    it 'should return 201 or 204 status code and body for known POST endpoints' do
      endpoints201 = %w[oauth/token collector/reward-redemptions]
      endpoints204 = %w[collector/2fa/code-resend]

      endpoints201.each do |endpoint|
        response = SpecUtils::Utils.post(endpoint)
        response.code.must_equal(201)
        response.body.wont_be_nil
      end

      endpoints204.each do |endpoint|
        response = SpecUtils::Utils.post(endpoint)
        response.code.must_equal(204)
        response.body.must_be_nil
      end
    end

    it 'should return 200 status code and body for known PUT endpoints' do
      endpoints = %w[collector/voucher collector/offers/123abc/optedIn collector/offers/123abc/optedInAndRedirect]

      endpoints.each do |endpoint|
        response = SpecUtils::Utils.put(endpoint)
        response.code.must_equal(200)
        response.body.wont_be_nil
      end
    end

    it 'should return status code of dynamic configuration' do
      path = 'collector/details'
      MockBackend::API.add_dynamic_configuration(path: path, status: 500)
      SpecUtils::Utils.get(path).code.must_equal(500)
    end

    # TODO: Fix me
    # it 'should retain dynamic configuration until init is called' do
    #   path = 'collector/details'
    #   MockBackend::API.add_dynamic_configuration(path: path, status: 500)
    #   SpecUtils::Utils.get(path).code.must_equal(500)
    #   SpecUtils::Utils.get(path).code.must_equal(500)
    #   MockBackend::API.init
    #   SpecUtils::Utils.get(path).code.must_equal(200)
    # end
  end
end
