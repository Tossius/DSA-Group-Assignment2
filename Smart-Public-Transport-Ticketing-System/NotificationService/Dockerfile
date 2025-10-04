FROM ballerina/ballerina:2201.10.2

# Switch to root to ensure write permissions
USER root

WORKDIR /app

# Copy project files
COPY . .

# Build the project
RUN bal build

EXPOSE 8084

# Run the compiled service
CMD ["bal", "run", "target/bin/notification_service.jar"]
