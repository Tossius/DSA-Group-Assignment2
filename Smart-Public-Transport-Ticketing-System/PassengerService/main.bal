import ballerina/http;
import ballerina/log;

// HTTP service listening on port 9001
service /passenger on new http:Listener(9001) {
    // Register new user
    resource function post register(@http:Payload UserRegistration userReg) returns json|http:BadRequest|http:Conflict|error {
        log:printInfo("Registering user: " + userReg.email);
        
        // Check if user already exists
        User|error existingUser = getUserByEmail(userReg.email);
        if existingUser is User {
            return <http:Conflict> {
                body: {
                    "error": "User already exists",
                    "message": "An account with this email already exists"
                }
            };
        }
        
        // Save to database
        int|error userId = saveUser(userReg, userReg.password);
        
        if userId is error {
            return <http:BadRequest> {
                body: {
                    "error": "Registration failed",
                    "message": userId.message()
                }
            };
        }
        
        return {
            "message": "User registered successfully",
            "userId": userId,
            "email": userReg.email
        };
    }
    
    // User login
    resource function post login(@http:Payload UserLogin loginData) returns json|http:NotFound|http:Unauthorized|error {
        log:printInfo("Login attempt for: " + loginData.email);
        
        // Try to get user
        User|error userResult = getUserByEmail(loginData.email);
        
        if userResult is error {
            return <http:NotFound> {
                body: {
                    "error": "User not found",
                    "message": "No account exists with this email address"
                }
            };
        }
        
        User user = userResult;
        
        // Check password
        if (user.password_hash == loginData.password) {
            return {
                "message": "Login successful",
                "userId": user.id,
                "name": user.full_name,
                "wallet_balance": user.wallet_balance
            };
        } else {
            return <http:Unauthorized> {
                body: {
                    "error": "Incorrect password",
                    "message": "The password you entered is incorrect"
                }
            };
        }
    }
    
    // Get user profile
    resource function get profile/[string email]() returns json|http:NotFound|error {
        User|error userResult = getUserByEmail(email);
        
        if userResult is error {
            return <http:NotFound> {
                body: {
                    "error": "User not found",
                    "message": "No user profile exists for this email"
                }
            };
        }
        
        User user = userResult;
        
        return {
            "id": user.id,
            "email": user.email,
            "name": user.full_name,
            "wallet_balance": user.wallet_balance
        };
    }
    
    // Get user's tickets
    resource function get tickets/[int userId]() returns Ticket[]|http:NotFound|error {
        // First check if user exists
        User|error userCheck = getUserById(userId);
        
        if userCheck is error {
            return <http:NotFound> {
                body: {
                    "error": "User not found",
                    "message": "No user exists with this ID"
                }
            };
        }
        
        return getUserTickets(userId);
    }
}