AdminService API (port 9096)

- GET `/admin/health`
- GET `/admin/routes`
- POST `/admin/routes`
  - body: { name, routeCode, startLocation, endLocation, stops?, distanceKm?, estimatedDurationMinutes? }
- GET `/admin/routes/{routeId}/trips`
- POST `/admin/routes/{routeId}/trips`
  - body: { tripCode, departureTime, arrivalTime, vehicleNumber?, totalSeats?, availableSeats?, baseFare, status? }
- POST `/admin/disruptions`
  - body: { type, title, message, severity, routeId?, tripId? }
- GET `/admin/reports/ticketSales`
- GET `/admin/reports/passengerTraffic`

Kafka
- Publishes to `schedule.updates` for events: ROUTE_CREATED, TRIP_CREATED, DISRUPTION

Notes
- Uses PostgreSQL via connection URL env in `types:AdminConfig` defaults.

