require 'active_support/core_ext/hash/slice'
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    # Support for only Easy Encryption as described here https://docs.adyen.com/manuals/easy-encryption <br>
    # Payment method will only be by credit card and credit card is referenced by an encrypted given string
    class Adyen12Gateway < Gateway

      ENDPOINTS ={
        'authorize' => 'authorise',
        'void' => 'cancel',
        'cancel_or_refund' => 'cancelOrRefund',
        'capture' => 'capture',
        'purchase' => 'authorise',
        'refund' => 'refund'
      }

      CUSTOMER_DATA = %i[
        shopperEmail shopperReference fraudOffset selectedBrand deliveryDate
        riskdata.deliveryMethod merchantOrderReference shopperInteraction
        shopperIP
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
        requires!(options, :merchantAccount, :login, :password)
        @login, @password, @merchantAccount = options.values_at(:login, :password, :merchantAccount)
        super
      end

      def purchase(money, payment, options={})
        requires!(options, :reference)
        post = initalize_post(options)
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)
        commit('purchase', post)
      end

      def authorize(money, payment, options={})
        requires!(options, :reference)
        post = initalize_post(options)
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authorize', post)
      end

      def capture(money, authorization, options={})
        post = initalize_post(options)
        add_invoice_for_modification(post, money, authorization, options)
        add_references(post, authorization, options)
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        post = initalize_post(options)
        add_invoice_for_modification(post, money, authorization, options)
        add_references(post, authorization, options)
        commit('refund', post)
      end

      def void(authorization, options={})
        post = initalize_post(options)
        add_references(post, authorization, options)
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
        amount = {
          value: amount(money),
          currency: options[:currency] || currency(money)
        }
        post[:reference] = options[:reference]
        post[:amount] = amount
      end

      def add_invoice_for_modification(post, money, authorization, options)
        amount = {
          value: amount(money),
          currency: options[:currency] || currency(money)
        }
        post[:modificationAmount] = amount
      end

      def add_payment(post, payment)
        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          add_credit_card_information(post, payment)
        else # card encrypted token
          add_additional_payment_data(post, payment)
        end
      end

      def add_credit_card_information(post, credit_card)
        card = {
          expiryMonth: credit_card.month,
          expiryYear: credit_card.year,
          holdereName: credit_card.name,
          number: credit_card.number,
          cvc: credit_card.verification_value
        }
        card.delete_if{|k,v| v.blank? }
        requires!(card, :expiryMonth, :expiryYear, :holdereName, :number, :cvc)
        post[:card] = card
      end

      # FIXME This part cannot be tested unless a browser is opened to generate a credit card token
      # Adyen only allow encrypted token to be valid 24 hours after generation
      # To be able to test this we need to open a browser
      def add_additional_payment_data(post, payment)
        post[:additionalData] ||= {}
        post[:additionalData][:"card.encrypted.json"] = payment
      end

      def add_references(post, authorization, options = {})
        post[:originalReference] = authorization
        post[:reference] = options[:reference]
      end

      def parse(body)
        return {} if body.blank?
        JSON.parse(body)
      end

      def commit(action, parameters)
        begin
          raw_response = ssl_post(url_for_action(action), post_data(action, parameters), request_headers)
          response = parse(raw_response)
        rescue ResponseError => e
          raw_response = e.response.body
          response = parse(raw_response)
        end
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
        when 'capture', 'refund'
          response['response'] == "[#{action}-received]"
        when 'void'
          response['response'] == "[cancel-received]"
        else
          false
        end
      end

      def message_from(action, response)
        case action.to_s
        when 'authorize', 'purchase'
          response['refusalReason'] || response['resultCode'] || response['message']
        when 'capture', 'refund', 'void'
          response['response'] || response['message']
        end
      end

      def authorization_from(action, response)
        case action.to_s
        when 'authorize', 'purchase'
          response['pspReference']
        when 'capture', 'refund', 'void'
          response['pspReference']
        else
          false
        end
      end

      def post_data(action, parameters = {})
        JSON.generate(parameters)
      end

      def initalize_post(options = {})
        {merchantAccount: options[:merchantAccount] || @merchantAccount}
      end

      def basic_auth
        Base64.encode64("#{@login}:#{@password}").gsub("\n", '')
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
