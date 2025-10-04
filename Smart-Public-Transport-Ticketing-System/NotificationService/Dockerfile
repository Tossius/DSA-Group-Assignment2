FROM ballerina/ballerina:2201.9.0

WORKDIR /app
COPY . /app

RUN bal build --cloud=docker

EXPOSE 9097

CMD ["bal", "run"]