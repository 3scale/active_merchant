require 'test_helper'

class Adyen12Test < Test::Unit::TestCase

  ### TESTS for EE only ###
  def setup
    @gateway = Adyen12Gateway.new(
      login: 'ws@example.com',
      password: 'password',
      merchantAccount: 'Mercantor'
    )

    # @credit_card = credit_card
    # Credit card is represented by an encrypted string
    # It is provided by adyen JS library in EE for the initial payment
    @credit_card = "adyenjs_0_1_10$aKV"
    @amount = 100

    @options = {
      reference: '1',
      shopperIP: '8.8.8.8'
    }
  end

  # Tests for fields requirements on authorize

  def test_authorize_requirements
    assert_raise ArgumentError, "Missing required parameter: reference" do
      @gateway.authorize(@amount, @encrypted_credit_card_string, {})
    end

    assert_raise ArgumentError, "Missing required parameter: shopperIP" do
      @gateway.authorize(@amount, @encrypted_credit_card_string, {reference: '1'})
    end
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal '64158', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_equal 'You have reached your payment threshold', response.message
    assert_failure response
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '12345', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'You do not have enough money', response.message
    assert_failure response
  end


  def test_successful_capture
  end

  def test_failed_capture
  end

  def test_successful_refund
  end

  def test_failed_refund
  end

  def test_successful_void
  end

  def test_failed_void
  end

  def test_successful_verify
  end

  def test_successful_verify_with_failed_void
  end

  def test_failed_verify
  end

  private

  def successful_authorize_response
    %(
    {
        "pspReference" : "8413547924770610",
        "resultCode" : "Authorised",
        "authCode": "64158"
    }
    )
  end

  def failed_purchase_response
    %(
     {
       "pspReference": "1234567890123456",
       "resultCode": "Refused",
       "authCode": "",
       "refusalReason": "You do not have enough money"
     }
    )
  end

  def successful_purchase_response
    %(
    {
        "pspReference" : "8413547924770610",
        "resultCode" : "Authorised",
        "authCode": "12345"
    }
    )
  end

  def failed_authorize_response
    %(
     {
       "pspReference": "1234567890123456",
       "resultCode": "Refused",
       "authCode": "",
       "refusalReason": "You have reached your payment threshold"
     }
    )
  end

  def successful_capture_response
  end

  def failed_capture_response
  end

  def successful_refund_response
  end

  def failed_refund_response
  end

  def successful_void_response
  end

  def failed_void_response
  end
end
