package payments.repository;

import java.util.List;

import payments.model.Order;

import org.springframework.data.repository.CrudRepository;

public interface OrderRepository extends CrudRepository<Order, Long>{
	List<Order> findById(int ID);
	List<Order> findAll();
}