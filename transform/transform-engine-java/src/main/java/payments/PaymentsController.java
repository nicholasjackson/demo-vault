package payments;

import java.io.IOException;
import java.sql.SQLException;

import javax.sql.DataSource;

import java.sql.Connection;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import payments.model.Order;
import payments.repository.OrderRepository;
import payments.vault.VaultClient;

@RestController
public class PaymentsController {
  @Autowired
  OrderRepository repository;
  
  @Autowired
  DataSource dataSource;

  private Environment env;

  Logger logger = LoggerFactory.getLogger(PaymentsController.class);
  VaultClient vaultClient;

  PaymentsController(Environment env) {
    this.env = env;
    vaultClient = new VaultClient(env.getProperty("vault.token"), env.getProperty("vault.addr"));
  }

  @PostMapping("/")
  @ResponseBody
  public PaymentResponse pay(@RequestBody PaymentRequest request) throws IOException {
    // tokenize the thing
    String tokenizedNumber = vaultClient.TokenizeCCNumber(request.getCardNumber());

      /*
      * Those who came before me
      * Lived through their vocations
      * From the past until completion
      * They'll turn away no more
      * And I still find it so hard
      * To say what I need to say
      * But I'm quite sure that you'll tell me
      * Just how I should feel today
      */
      Order newOrder = repository.save(new Order(tokenizedNumber));

      logger.info("New payment");
      logger.info("CC Number: {}", request.getCardNumber());
      logger.info("Tokenized Number: {}", tokenizedNumber);
      logger.info("DB record ID: {}", newOrder.getId());

      return new PaymentResponse(newOrder.getId());
  }
  
  @GetMapping("/health")
  @ResponseBody
  public HealthResponse health() throws IOException {
      logger.info("Health Check");
      
      String dbHealth = "OK";
      String vaultHealth = "OK";
     
      try {
        Connection con = dataSource.getConnection();
        
        if (con.isClosed()) {
          dbHealth = "Fail";
        }
      } catch (SQLException e) {
        dbHealth = "Fail";
      }
    
      if (!vaultClient.IsOK()) {
        vaultHealth = "Fail";
      }

      return new HealthResponse(vaultHealth, dbHealth);
  }

}