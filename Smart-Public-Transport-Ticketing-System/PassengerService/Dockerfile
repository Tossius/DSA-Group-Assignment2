FROM ballerina/ballerina:2201.10.0

WORKDIR /home/ballerina

# Copy Ballerina.toml first
COPY Ballerina.toml .

# Copy source files
COPY main.bal .
COPY database.bal .
COPY types.bal .

# Build will auto-generate Dependencies.toml
RUN bal build

# Expose port
EXPOSE 9001

# Run the application
CMD bal run