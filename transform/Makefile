image_name="nicholasjackson/transform-demo"

build_docker_go:
	docker build -t ${image_name}:go -f transform-engine-go/Dockerfile ./transform-engine-go

build_docker_java:
	docker build -t ${image_name}:java -f transform-engine-java/Dockerfile ./transform-engine-java

build_docker_all: build_docker_go build_docker_java

push_all: build_docker_all
	docker push ${image_name}:go
	docker push ${image_name}:java