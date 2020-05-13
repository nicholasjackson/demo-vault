package payments;

import com.fasterxml.jackson.annotation.JsonGetter;

public class HealthResponse {
  private String vault;
  private String db;

  @JsonGetter("vault")
  public String getVault() {
    return vault;
  }

  @JsonGetter("db")
  public String getDB() {
    return db;
  }

  HealthResponse(String vault, String db) {
    this.db = db;
    this.vault = vault;
  }
}