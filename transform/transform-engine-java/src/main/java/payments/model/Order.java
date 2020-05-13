package payments.model;

import java.io.Serializable;
import java.math.BigInteger;
import java.time.LocalDateTime;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;

@Entity
@Table(name = "orders")
public class Order implements Serializable {
 
	private static final long serialVersionUID = -2343243243242432341L;
	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Integer id;
 
	@Column(name = "card_number")
	private String cardNumber;
 
	@Column(name = "created_at")
	private LocalDateTime createdAt;
  
  @Column(name = "updated_at")
	private LocalDateTime updatedAt;
  
  @Column(name = "deleted_at")
	private LocalDateTime deletedAt;
 
	protected Order() {
	}
 
	public Order(String cardNumber) {
		this.cardNumber = cardNumber;
    this.createdAt = LocalDateTime.now();
    this.updatedAt = LocalDateTime.now();
	}
 
	@Override
	public String toString() {
    return String.format("Customer[id=%d, cardNumber='%s']", id, cardNumber);
  }
  
  public Integer getId() {
    return this.id;
  }

	public String getCardNumber() {
    return cardNumber;
  }
  
  public void setCardNumber(String cardNumber) {
    this.cardNumber = cardNumber;
  }
  
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
  
  public void setCreatedAt(LocalDateTime createdAt) {
    this.createdAt = createdAt;
  }
  
  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }
  
  public void setUpdatedAt(LocalDateTime updatedAt) {
    this.updatedAt = updatedAt;
  }
}