package payments;

import com.fasterxml.jackson.annotation.JsonGetter;
import com.fasterxml.jackson.annotation.JsonSetter;

class PaymentRequest {

  private String cardNumber;

  @JsonGetter("card_number")
  public String getCardNumber() {
    return this.cardNumber;
  }

  @JsonSetter("card_number")
  public void setCardNumber(final String number) {
    this.cardNumber = number;
  }
}