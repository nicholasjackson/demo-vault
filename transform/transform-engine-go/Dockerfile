FROM golang:1.13 as build


WORKDIR /go/src/github.com/nicholasjackson/demo-vault/transform-engine-go
COPY . .

RUN go get -d -v ./... && \
    CGO_ENABLED=0 go build -o /bin/server ./

FROM alpine:latest

RUN apk add curl

RUN mkdir /app
COPY --from=build /bin/server /app/server

ENTRYPOINT [ "/app/server" ]