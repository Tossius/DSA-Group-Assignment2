-- Users table
CREATE TABLE users (
 id SERIAL PRIMARY KEY,
 email VARCHAR(255) UNIQUE NOT NULL,
 password_hash VARCHAR(255) NOT NULL,
 full_name VARCHAR(255) NOT NULL,
 role VARCHAR(50) NOT NULL,
 wallet_balance DECIMAL(10, 2) DEFAULT 0.00,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Routes table
CREATE TABLE routes (
 id SERIAL PRIMARY KEY,
 name VARCHAR(255) NOT NULL,
 route_code VARCHAR(50) UNIQUE NOT NULL,
 start_location VARCHAR(255) NOT NULL,
 end_location VARCHAR(255) NOT NULL,
 stops JSONB,
 distance_km DECIMAL(6, 2),
 estimated_duration_minutes INTEGER,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trips table
CREATE TABLE trips (
 id SERIAL PRIMARY KEY,
 route_id INTEGER REFERENCES routes(id),
 trip_code VARCHAR(50) UNIQUE NOT NULL,
 departure_time TIMESTAMP NOT NULL,
 arrival_time TIMESTAMP NOT NULL,
 vehicle_number VARCHAR(50),
 total_seats INTEGER DEFAULT 50,
 available_seats INTEGER DEFAULT 50,
 base_fare DECIMAL(8, 2) NOT NULL,
 status VARCHAR(50) DEFAULT 'SCHEDULED',
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tickets table
CREATE TABLE tickets (
 id SERIAL PRIMARY KEY,
 ticket_number VARCHAR(100) UNIQUE NOT NULL,
 user_id INTEGER REFERENCES users(id),
 trip_id INTEGER REFERENCES trips(id),
 ticket_type VARCHAR(50) NOT NULL,
 amount DECIMAL(8, 2) NOT NULL,
 status VARCHAR(50) DEFAULT 'CREATED',
 purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 validation_date TIMESTAMP,
 expiry_date TIMESTAMP
);

-- Payments table
CREATE TABLE payments (
 id SERIAL PRIMARY KEY,
 payment_reference VARCHAR(100) UNIQUE NOT NULL,
 ticket_id INTEGER REFERENCES tickets(id),
 user_id INTEGER REFERENCES users(id),
 amount DECIMAL(10, 2) NOT NULL,
 status VARCHAR(50) DEFAULT 'PENDING',
 transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notifications table
CREATE TABLE notifications (
 id SERIAL PRIMARY KEY,
 user_id INTEGER REFERENCES users(id),
 notification_type VARCHAR(50) NOT NULL,
 title VARCHAR(255) NOT NULL,
 message TEXT NOT NULL,
 is_read BOOLEAN DEFAULT FALSE,
 sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (email, password_hash, full_name, role, wallet_balance) VALUES
('admin@windhoek.com', 'hashed_password', 'Admin User', 'ADMIN', 0.00),
('passenger1@test.com', 'hashed_password', 'John Doe', 'PASSENGER', 100.00);

INSERT INTO routes (name, route_code, start_location, end_location, distance_km, estimated_duration_minutes) VALUES
('City to Airport', 'R001', 'City Center', 'Airport', 45.5, 60),
('Northern Loop', 'R002', 'Katutura', 'Windhoek West', 25.3, 45);

INSERT INTO trips (route_id, trip_code, departure_time, arrival_time, vehicle_number, base_fare) VALUES
(1, 'TRIP001', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '3 hours', 'BUS-101', 25.00),
(2, 'TRIP002', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '2 hours', 'BUS-201', 15.00);