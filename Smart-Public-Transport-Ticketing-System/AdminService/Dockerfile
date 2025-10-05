FROM ballerina/ballerina:2201.12.9

WORKDIR /app
COPY . /app

RUN bal build

EXPOSE 9096

CMD ["bal", "run"]


