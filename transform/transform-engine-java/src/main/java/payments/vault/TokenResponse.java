package payments.vault;

import com.fasterxml.jackson.annotation.JsonSetter;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public class TokenResponse {
  private TokenResponseData data;

  public TokenResponse() {
    super();
  }

  public TokenResponse(TokenResponseData data) {
    super();

    this.data = data;
  }

  public TokenResponseData getTokenResponseData() {
    return this.data;
  }

  @JsonSetter("data")
  public void setTokenResponseData(TokenResponseData data) {
    this.data = data;
  }

  @JsonIgnoreProperties(ignoreUnknown = true)
  public class TokenResponseData {
    private String encodedValue;

    public TokenResponseData() {
      super();
    }

    public TokenResponseData(String value) {
      super();

      this.encodedValue = value;
    }

    public String getEncodedValue() {
      return this.encodedValue;
    }

    @JsonSetter("encoded_value")
    public void setEncodedValue(String value) {
      this.encodedValue = value;
    }
  }
}