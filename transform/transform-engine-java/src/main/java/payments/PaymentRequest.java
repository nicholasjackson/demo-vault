package payments;

import com.fasterxml.jackson.annotation.JsonGetter;
import com.fasterxml.jackson.annotation.JsonSetter;

class PaymentRequest {

  private String cardNumber;
  private String expiration;
  private String cv2;

  @JsonGetter("card_number")
  public String getCardNumber() {
    return this.cardNumber;
  }

  @JsonSetter("card_number")
  public void setCardNumber(final String number) {
    this.cardNumber = number;
  }
  
  @JsonGetter("expiration")
  public String getExpiration() {
    return this.expiration;
  }

  @JsonSetter("expiration")
  public void setExpiration(final String exp) {
    this.expiration = exp;
  }
  
  @JsonGetter("cv2")
  public String getCV2() {
    return this.cv2;
  }

  @JsonSetter("cv2")
  public void setCV2(final String cv2) {
    this.cv2 = cv2;
  }
}