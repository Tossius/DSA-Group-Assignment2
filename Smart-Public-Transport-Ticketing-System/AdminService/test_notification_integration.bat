@echo off
echo Testing AdminService Notification Integration
echo ============================================

echo.
echo 1. Testing Route Creation (should publish route created event)
curl -X POST http://localhost:9096/admin/routes ^
  -H "Content-Type: application/json" ^
  -d "{\"name\":\"Test Route\",\"routeCode\":\"TR001\",\"startLocation\":\"City A\",\"endLocation\":\"City B\",\"distanceKm\":50.5,\"estimatedDurationMinutes\":60}"

echo.
echo.
echo 2. Testing Trip Creation (should publish trip created event)
curl -X POST http://localhost:9096/admin/routes/1/trips ^
  -H "Content-Type: application/json" ^
  -d "{\"tripCode\":\"TR001-001\",\"departureTime\":\"2024-01-15T08:00:00Z\",\"arrivalTime\":\"2024-01-15T09:00:00Z\",\"vehicleNumber\":\"BUS001\",\"totalSeats\":50,\"baseFare\":25.00,\"status\":\"ACTIVE\"}"

echo.
echo.
echo 3. Testing Schedule Update (should publish schedule update event)
curl -X POST http://localhost:9096/admin/scheduleUpdates ^
  -H "Content-Type: application/json" ^
  -d "{\"update_type\":\"DELAY\",\"message\":\"Trip delayed by 15 minutes due to traffic\",\"trip_code\":\"TR001-001\",\"route_name\":\"Test Route\",\"new_departure_time\":\"2024-01-15T08:15:00Z\",\"new_arrival_time\":\"2024-01-15T09:15:00Z\"}"

echo.
echo.
echo 4. Testing Disruption (should publish disruption event)
curl -X POST http://localhost:9096/admin/disruptions ^
  -H "Content-Type: application/json" ^
  -d "{\"disruption_type\":\"BREAKDOWN\",\"reason\":\"Vehicle mechanical failure\",\"trip_code\":\"TR001-001\",\"route_name\":\"Test Route\"}"

echo.
echo.
echo Integration test completed!
echo Check Kafka topics 'schedule.updates' and 'trip.disruptions' for published events.
echo Check NotificationService logs for consumed events.
