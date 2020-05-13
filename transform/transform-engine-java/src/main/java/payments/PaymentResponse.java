package payments;

import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonGetter;

class PaymentResponse {

	private Integer transactionid;

  @JsonGetter("transaction_id")
	public Integer getId() {
		return transactionid;
	}

	PaymentResponse(Integer id) {
		this.transactionid = id;
	}
}