FROM ballerina/ballerina:2201.10.0

WORKDIR /home/ballerina

# Copy all source files
COPY Ballerina.toml .
COPY main.bal .
COPY database.bal .
COPY types.bal .

# Build the application
RUN bal build

# Expose port
EXPOSE 9002

# Run the application
CMD bal run