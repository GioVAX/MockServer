require_relative 'spec_helper'

# Test class for admin endpoints
class SpecAdmin < Minitest::Spec
  describe 'Admin' do
    before(:all) do
      MockBackend::API.reload_endpoints(nil, file: 'mobile_endpoints')
    end

    after(:all) do
      MockBackend::Boot.exit
    end

    it 'should reload endpoints' do
      MockBackend::API.reload_endpoints
      SpecUtils::Utils.get('collector/details').code.must_equal(404)

      MockBackend::API.reload_endpoints(nil, file: 'mobile_endpoints')
      SpecUtils::Utils.get('collector/details').code.must_equal(200)
    end

    it 'should reset responses' do
      SpecUtils::Utils.get('collector/details')
      MockBackend::API.init
      MockBackend::API.display_responses.must_be_empty
    end

    it 'should reset requests' do
      SpecUtils::Utils.get('collector/details')
      MockBackend::API.init
      MockBackend::API.display_requests.must_be_empty
    end

    it 'should reset analytics requests' do
      SpecUtils::Utils.get('eluminate?tid=1&pi=Offer+Details+Screen&cg=Offers')
      MockBackend::API.init
      MockBackend::API.display_analytics_requests.must_be_empty
    end

    it 'should display responses' do
      MockBackend::API.init
      SpecUtils::Utils.get('collector/details')
      MockBackend::API.display_responses.wont_be_empty
    end

    it 'should display requests' do
      MockBackend::API.init
      SpecUtils::Utils.get('collector/details')
      MockBackend::API.display_requests.wont_be_empty
    end

    it 'should display analytics requests' do
      MockBackend::API.init
      SpecUtils::Utils.get('eluminate?tid=1&pi=Offer+Details+Screen&cg=Offers')
      MockBackend::API.display_analytics_requests.wont_be_empty
    end

    it 'should display status' do
      status = MockBackend::API.display_status
      status[:response_delay].must_be_nil
      status[:forced_type].must_be_nil
      status[:forced_status].must_be_nil
      status[:forced_body].must_be_nil
      status[:endpoints].wont_be_nil
    end

    it 'should display configured endpoints' do
      MockBackend::API.display_configured_endpoints.wont_be_empty
    end

    # it 'should set forced response' do
    #   forced = {}
    #   forced[:delay] = '111'
    #   forced[:type] = 'test'
    #   forced[:status] = '400'
    #   forced[:body] = JSON.generate(["test"])
    #   MockBackend::API.set_forced_response(forced)
    #
    #   status = MockBackend::API.display_status
    #   status[:response_delay].must_equal(111)
    #   status[:forced_type].must_equal('test')
    #   status[:forced_status].must_equal(400)
    #   status[:forced_body].must_equal(["test"])
    # end
  end
end
