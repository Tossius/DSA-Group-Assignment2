// types.bal - AdminService Type Definitions for Notification Integration

// Event when schedule is updated (routes/trips created/modified)
public type ScheduleUpdateEvent record {|
    int? trip_id?;
    string? trip_code?;
    string? route_name?;
    string update_type; // NEW_ROUTE, NEW_TRIP, SCHEDULE_CHANGE
    string message;
    string? new_departure_time?;
    string? new_arrival_time?;
    int[]? affected_user_ids?; // Users with tickets for this trip
    string timestamp;
|};

// Event when a trip is disrupted
public type TripDisruptionEvent record {|
    int? trip_id?;
    string? trip_code?;
    string? route_name?;
    string disruption_type; // DELAY, CANCELLATION, BREAKDOWN, SERVICE_DISRUPTION
    string reason;
    int? delay_minutes?;
    int[]? affected_user_ids?; // Users with tickets for this trip
    string timestamp;
|};

// Route creation event
public type RouteCreatedEvent record {|
    int route_id;
    string route_code;
    string route_name;
    string start_location;
    string end_location;
    decimal distance_km;
    int estimated_duration_minutes;
    string timestamp;
|};

// Trip creation event
public type TripCreatedEvent record {|
    int trip_id;
    int route_id;
    string trip_code;
    string route_name;
    string departure_time;
    string arrival_time;
    string vehicle_number;
    int total_seats;
    decimal base_fare;
    string timestamp;
|};

// Disruption request from admin
public type DisruptionRequest record {|
    string disruption_type; // DELAY, CANCELLATION, BREAKDOWN, SERVICE_DISRUPTION
    string reason;
    int? trip_id?;
    string? trip_code?;
    string? route_name?;
    int? delay_minutes?;
    string? affected_routes?; // Comma-separated route codes
|};
