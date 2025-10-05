public type TicketRequest record {|
    int user_id;
    int trip_id;
    string ticket_type;
    decimal amount;
|};

public type Ticket record {|
    int id?;
    string ticket_number;
    int user_id;
    int trip_id;
    string ticket_type;
    decimal amount;
    string status;
    string purchase_date?;
    string? validated_at?;
|};

public type TicketValidation record {|
    string ticket_number;
    int validator_id;
|};

public type ValidationResponse record {|
    boolean valid;
    string message;
    Ticket? ticket?;
|};

public type KafkaTicketRequest record {|
    string ticket_number;
    int user_id;
    int trip_id;
    string ticket_type;
    decimal amount;
    string timestamp;
|};

public type KafkaPaymentConfirmation record {|
    string ticket_number;
    boolean success;
    string payment_id?;
    string timestamp;
|};