FROM ballerina/ballerina:2201.9.0

WORKDIR /app
COPY . /app

# Rename ballerina.toml to Ballerina.toml for compatibility
RUN mv ballerina.toml Ballerina.toml

# Fix permissions and build
RUN chmod -R 755 /app && bal build

EXPOSE 9096

CMD ["bal", "run", "target/bin/service.jar"]
