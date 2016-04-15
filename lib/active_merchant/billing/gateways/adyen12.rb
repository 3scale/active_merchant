require 'active_support/core_ext/hash/slice'
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    # Support for only Easy Encryption as described here https://docs.adyen.com/manuals/easy-encryption <br>
    # Payment method will only be by credit card and credit card is referenced by an encrypted given string
    # TODO
    class Adyen12Gateway < Gateway

      ENDPOINTS ={
        'authorize' => 'authorise',
        'cancel' => 'cancel',
        'cancel_or_refund' => 'cancelOrRefund',
        'capture' => 'capture',
        'purchase' => 'authorise',
        'refund' => 'refund'
      }

      CUSTOMER_DATA = %i[
        shopperEmail shopperReference fraudOffset selectedBrand deliveryDate
        riskdata.deliveryMethod merchantOrderReference shopperInteraction
      ]

      self.test_url = 'https://pal-test.adyen.com/pal/servlet/Payment/v12'
      # This is generic endpoint. Merchant-Specific endpoints are recommended  https://docs.adyen.com/manuals/api-manual#apiendpoints
      self.live_url = 'https://pal-live.adyen.com/pal/servlet/Payment/v12'

      self.supported_countries = ['AR', 'AT', 'BE', 'BR', 'CA', 'CH', 'CL', 'CN', 'CO', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR', 'GB', 'HK', 'ID', 'IE', 'IL', 'IN', 'IT', 'JP', 'KR', 'LU', 'MX', 'MY', 'NL', 'NO', 'PA', 'PE', 'PH', 'PL', 'PT', 'RU', 'SE', 'SG', 'TH', 'TR', 'TW', 'US', 'VN', 'ZA']
      self.default_currency = 'USD'
      self.money_format = :cents
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb, :dankort, :maestro]

      self.homepage_url = 'http://www.example.net/'
      self.display_name = 'Adyen v12'

      def initialize(options={})
        requires!(options, :login, :password, :merchantAccount)
        @login, @password, @merchantAccount = options.values_at(:login, :password, :merchantAccount)
        super
      end

      def purchase(money, payment, options={})
        post = initalize_post
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('purchase', post)
      end

      def authorize(money, payment, options={})
        post = initalize_post
        requires!(options, :reference, :shopperIP)
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authorize', post)
      end

      def capture(money, authorization, options={})
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        commit('refund', post)
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      private

      def add_customer_data(post, options)
        post.merge!(options.slice(*CUSTOMER_DATA))
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, payment)
        post[:additionalData] ||= {}
        post[:additionalData][:"card.encrypted.json"] = payment
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(action, parameters)
        raw_response = ssl_post(url_for_action(action), post_data(action, parameters), request_headers)
        response = parse(raw_response)

        Response.new(
          success_from(action, response),
          message_from(action, response),
          response,
          authorization: authorization_from(action, response),
          test: test?
        )
      end

      def success_from(action, response)
        case action.to_s
        when 'authorize', 'purchase'
          ['Authorised', 'Received', 'RedirectShopper'].include?(response['resultCode'])
        else
          false
        end
      end

      def message_from(action, response)
        case action.to_s
        when 'authorize', 'purchase'
          response['refusalReason']
        end
      end

      def authorization_from(action, response)
        case action.to_s
        when 'authorize', 'purchase'
          response['authCode']
        else
          false
        end
      end

      def post_data(action, parameters = {})
      end

      def initalize_post
        {merchantAccount: @merchantAccount}
      end

      def basic_auth
        Base64.encode64("#{@login}:#{@password}")
      end

      def request_headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Basic #{basic_auth}"
        }
      end

      def url_for_action(action)
        url = (test? ? test_url : live_url)
        "#{url}/#{ENDPOINTS[action.to_s]}"
      end
    end
  end
end
