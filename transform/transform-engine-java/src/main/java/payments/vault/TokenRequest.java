package payments.vault;

import com.fasterxml.jackson.annotation.JsonGetter;
import com.fasterxml.jackson.annotation.JsonSetter;

public class TokenRequest {
  private String value;

  public TokenRequest(final String value) {
    super();

    this.value = value;
  }

  public void setValue(final String value) {
    this.value = value;
  }

  public String getValue() {
    return this.value;
  }
}