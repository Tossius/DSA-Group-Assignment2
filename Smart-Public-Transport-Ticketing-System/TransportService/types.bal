// Route types
type Route record {|
    int id?;
    string name;
    string route_code;
    string start_location;
    string end_location;
    json? stops;
    decimal? distance_km;
    int? estimated_duration_minutes;
    string? created_at;
|};

type RouteCreate record {|
    string name;
    string route_code;
    string start_location;
    string end_location;
    decimal? distance_km;
    int? estimated_duration_minutes;
|};

// Trip types
type Trip record {|
    int id?;
    int route_id;
    string trip_code;
    string departure_time;
    string arrival_time;
    string? vehicle_number;
    int total_seats;
    int available_seats;
    decimal base_fare;
    string status;
    string? created_at;
|};

type TripCreate record {|
    int route_id;
    string trip_code;
    string departure_time;
    string arrival_time;
    string? vehicle_number;
    int total_seats;
    decimal base_fare;
|};

type TripUpdate record {|
    string? status;
    int? available_seats;
|};