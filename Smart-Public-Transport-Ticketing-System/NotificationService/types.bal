// NotificationService/types.bal

public type Notification record {|
    int id?;
    int user_id;
    string message;
    string notification_type; // TICKET_VALIDATED, SCHEDULE_UPDATE, PAYMENT_SUCCESS, GENERAL
    boolean is_read?;
    string created_at?;
|};

public type NotificationRequest record {|
    int user_id;
    string message;
    string notification_type;
|};

public type KafkaTicketValidated record {|
    string ticket_number;
    int validator_id;
    string timestamp;
|};

public type KafkaScheduleUpdate record {|
    string alert_type;
    string message;
    int? route_id?;
    int? trip_id?;
    string severity;
|};