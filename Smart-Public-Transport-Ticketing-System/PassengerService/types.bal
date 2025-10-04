type User record {|
    int id?;
    string email;
    string password_hash;
    string full_name;
    string role;
    decimal wallet_balance?;
    string created_at?;  // Add this field
|};

public type UserRegistration record {|
    string email;
    string password;
    string full_name;
|};

type UserLogin record {|
    string email;
    string password;
|};

type Ticket record {|
    int id;
    string ticket_number;
    int user_id;
    int? trip_id;
    string ticket_type;
    decimal amount;
    string status;
    string purchase_date;
|};