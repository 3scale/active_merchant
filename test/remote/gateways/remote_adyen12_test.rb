require 'test_helper'

class RemoteAdyen12Test < Test::Unit::TestCase
  def setup
    @gateway = Adyen12Gateway.new(fixtures(:adyen12))

    @amount = 100

    # https://www.adyen.com/home/support/knowledgebase/implementation-articles?article=kb_imp_17
    @credit_card = credit_card('4111111111111111',
    :month => 8,
    :year => 2018,
    :first_name => 'Test',
    :last_name => 'Card',
    :verification_value => '737',
    :brand => 'visa'
    )

    # This crypted card needs to be generated every 24 hours for the tests to run
    adyenjs = %Q(adyenjs_0_1_16$ub3bdU8BS+Us0HHO/mTQox/3cG8qlQ7C+NgRY0SC32PDPdqqOQ84Nk8BHgw+8TnBbAYDH++RnnU0gfiEEKi2TH7fZ/ayJqR6iyZeblOgjC8MYTx2Xnbhzj5LbkGsSTu0tbY2H8PMH0cpEBIX/jMsaLSZqPFH72Apj/RxaVBBTLe7cHYZav+Z2pDzfRAruBXDvMNp47BDK/o9h9Q5lmeN8uudJSiHHqTzdX8HfmfamUrftsPiXi8uxmsdAO0iDahQk8Q/G6Rbxdmf2MOl8fzTeyQ1rpDbSQegYuihi4y50EvRw4EmrEmTHyB9EsyWSYCdreO+PfRNgpJPijV3e7PXXQ==$nLUy0SGhf0V/o5hSmy8OrZgYdivEj08MZk2EYNkz1IwAyupQLH1b1XYBlZQp4NnljgayHsWFWPE1yT2FZlKa+P9g8eztHbd4H1TUtKu3WyfncQe9sr1Ax2JLC9Ju5mnT7xAxNh3suqXhbuLVFRcXWoujhkYtwxZo63EBCDW2Fyue2fHI1PFqHa5vKC9HKKhziTX3EXjsw29oTZOIREXogHoCuEXHQ025K7QOs3tXKoDbDzUyDhAnFKZX+/9PSFuKKDkt22kXSIvWlE8M2XrQOUcihT3xz9eOae4PMGNSNedoJhNuUyiOtadvlvG6tURJOk1Ny4EGrdkUh5sr0zkHByozrQCvrWlL3zD8gHRDhLt7QhRNCBrJ6NDBX3n9pBOStbh3vpD7We0Gp8dV2Lv7t5r24iB191H1N0sXvV5dJO6gMmHpatCVKGQ58EIHH1YXXmXRD5KDUec3vKc8Gwc3T+WCp/asuEfkqMH3ouqKA4c80m5ENK84mKb2fnONNVtazQt77/NM6h2NGDbNIZHKOV7P2LvsmR5ccEIn+8U5SGyoxN3PKG174Dl1NwKWdrgfjpC7DkOstpwRCVwycF+byBuyTCT7VBRJBvFzUKaOWdreCiVKGBT64op0r91KI2h/vpZzahvvxlnMyBYIVETrSkIfww1D7f8vfHop5SYQpiSlz9Z7xYRGqJAbLV6sYnIub0mYSvmFH4O5)
    @credit_card = adyenjs

    @declined_card = credit_card('4000300011112220')

    @options = {
      reference: '3',
      shopperEmail: "s.hopper@test.com",
      shopperIP: "61.294.12.12",
      shopperReference: "Simon Hopper"
    }
    @recurring = {
      recurring:  'RECURRING'
    }
    @recurring_submission = {
      shopperInteraction: 'ContAuth',
      selectedRecurringDetailReference: 'LATEST'
    }
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '[capture-received]', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Refused', response.message
  end

  def test_successful_recurring_purchase
    response = @gateway.authorize_recurring(0, @credit_card, @options.merge(@recurring))
    recurring = @gateway.submit_recurring(1500, response.authorization, @options.merge(@recurring.merge(@recurring_submission)))
    assert_success response
    assert_success recurring
    assert_equal 'Authorised', response.message
    assert_equal 'Authorised', recurring.message
  end

  def test_failed_recurring_purchase
    response = @gateway.authorize_recurring(0, @credit_card, @options.merge(@recurring))
    recurring = @gateway.submit_recurring(1500, response.authorization, @options.merge({
      shopperInteraction: 'ContAuth',
      selectedRecurringDetailReference: 'NonExistent'
    }))
    assert_success response
    assert_failure recurring
    assert_equal 'Unknown', recurring.message
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization, @options.slice(:reference))
    assert_success capture
  end

  def test_failed_authorize
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(nil, '')
    assert_failure response
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount-1, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(0, '')
    assert_failure response
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match 'Authorised', response.message
  end

  def test_failed_verify
    response = @gateway.verify(@declined_card, @options)
    assert_failure response
    assert_match 'Refused', response.message
  end

  def test_invalid_login
    gateway = Adyen12Gateway.new(
      login: '',
      password: '',
      merchantAccount: 'hello'
    )
    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end
end
