// types.bal - Notification Service Type Definitions

// Notification record matching database schema
public type Notification record {|
    int id?;
    int user_id;
    string notification_type;
    string title;
    string message;
    string severity = "INFO"; // INFO, WARNING, CRITICAL
    json metadata?;
    boolean is_read = false;
    string timestamp?;
|};

// Request to create a notification
public type CreateNotificationRequest record {|
    int user_id;
    string notification_type;
    string title;
    string message;
    string severity?;
    json metadata?;
|};

// Response for notification operations
public type NotificationResponse record {|
    int id;
    int user_id;
    string notification_type;
    string title;
    string message;
    string severity;
    json metadata?;
    boolean is_read;
    string timestamp;
|};

// Kafka Event Types
// Event when a ticket is validated
public type TicketValidatedEvent record {|
    int ticket_id;
    int user_id;
    int trip_id;
    string ticket_number;
    string validation_date;
    string trip_code?;
    string route_name?;
|};

// Event when schedule is updated
public type ScheduleUpdateEvent record {|
    int trip_id;
    string trip_code;
    string route_name;
    string update_type; // DELAY, CANCELLATION, RESCHEDULED
    string message;
    string? new_departure_time;
    string? new_arrival_time;
    int[] affected_user_ids?; // Users with tickets for this trip
|};

// Event when a trip is disrupted
public type TripDisruptionEvent record {|
    int trip_id;
    string trip_code;
    string route_name;
    string disruption_type; // DELAY, CANCELLATION, BREAKDOWN
    string reason;
    int delay_minutes?;
    int[] affected_user_ids; // Users with tickets for this trip
|};

// Event when payment is processed
public type PaymentProcessedEvent record {|
    int payment_id;
    int user_id;
    int ticket_id;
    string payment_reference;
    decimal amount;
    string status; // SUCCESS, FAILED
    string transaction_date;
|};

// API Response wrapper
public type ApiResponse record {|
    boolean success;
    string message;
    json data?;
|};

// Get notifications query parameters
public type NotificationFilter record {|
    int user_id;
    boolean? unread_only;
    string? notification_type;
    int 'limit = 50;
    int offset = 0;
|};