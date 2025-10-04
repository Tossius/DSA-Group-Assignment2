import ballerina/http;
import ballerina/log;

// HTTP service listening on port 9001
service /passenger on new http:Listener(9001) {
    // Register new user
    // POST http://localhost:9001/passenger/register
    resource function post register(@http:Payload UserRegistration userReg) returns json|error {
        log:printInfo("Registering user: " + userReg.email);
        
        // Save to database without hashing (temporary)
        int userId = check saveUser(userReg, userReg.password);
        
        return {
            "message": "User registered successfully",
            "userId": userId,
            "email": userReg.email
        };
    }
    
    // User login
    // POST http://localhost:9001/passenger/login
    resource function post login(@http:Payload UserLogin loginData) returns json|error {
        log:printInfo("Login attempt for: " + loginData.email);
        
        // Get user from database
        User user = check getUserByEmail(loginData.email);
        
        // Check if password matches (no hashing for now)
        if (user.password_hash == loginData.password) {
            return {
                "message": "Login successful",
                "userId": user.id,
                "name": user.full_name,
                "wallet_balance": user.wallet_balance
            };
        } else {
            return error("Invalid credentials");
        }
    }
    
    // Get user profile
    // GET http://localhost:9001/passenger/profile/email@test.com
    resource function get profile/[string email]() returns json|error {
        User user = check getUserByEmail(email);
        
        return {
            "id": user.id,
            "email": user.email,
            "name": user.full_name,
            "wallet_balance": user.wallet_balance
        };
    }
    
    // Get user's tickets
    // GET http://localhost:9001/passenger/tickets/1
    resource function get tickets/[int userId]() returns Ticket[]|error {
        return getUserTickets(userId);
    }
}