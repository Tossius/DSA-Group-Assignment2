<<<<<<< HEAD
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
=======
FROM mcr.microsoft.com/dotnet/aspnet:7.0
>>>>>>> a293d76a25d58fb62d19e65bdd1b76ac1f92656b
