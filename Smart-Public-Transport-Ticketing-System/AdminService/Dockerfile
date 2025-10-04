FROM ballerina/ballerina:2201.9.0

WORKDIR /app

# Copy source files
COPY Ballerina.toml types.bal service.bal ./

# Build the project
RUN bal build

EXPOSE 9096

CMD ["bal", "run", "target/bin/service.jar"]
