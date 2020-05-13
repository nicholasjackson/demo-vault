package payments.vault;

import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.OutputStream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

public class VaultClient {
  private String token;
  private String serverURI;

  Logger logger = LoggerFactory.getLogger(VaultClient.class);

  public VaultClient(String token, String serverURI) {
    this.token = token;
    this.serverURI = serverURI;
  }

  public Boolean IsOK() throws IOException {
    URL url = new URL(this.serverURI+ "/v1/sys/health");
    HttpURLConnection con = (HttpURLConnection)url.openConnection();
    con.setRequestMethod("GET");
    con.setRequestProperty("X-Vault-Token", this.token);
    
    int status = con.getResponseCode();
    if (status != 200) {
      return false;
    }

    return true;
  }


  public String TokenizeCCNumber(String cardNumber) throws IOException, JsonProcessingException {
    // create the request
    TokenRequest req = new TokenRequest(cardNumber);
    
    // convert the POJO to a byte array 
    ObjectMapper mapper = new ObjectMapper();
    mapper.enable(SerializationFeature.INDENT_OUTPUT);
    byte[] byteRequest = mapper.writeValueAsBytes(req);
      
    // make a call to vault to process the request
    URL url = new URL(this.serverURI+ "/v1/transform/encode/payments");
    HttpURLConnection con = (HttpURLConnection)url.openConnection();
    con.setDoOutput(true);    
		con.setRequestMethod("POST");
		con.setRequestProperty("Content-Type", "application/json; utf-8");
    con.setRequestProperty("Accept", "application/json");
    con.setRequestProperty("X-Vault-Token", this.token);

    // write the body
    try(OutputStream os = con.getOutputStream()) {
      os.write(byteRequest, 0, byteRequest.length);           
    }

    // read the response
    TokenResponse resp = new ObjectMapper()
      .readerFor(TokenResponse.class)
      .readValue(con.getInputStream());

    return resp.getTokenResponseData().getEncodedValue();
  }
}