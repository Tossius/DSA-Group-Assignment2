-- Smart Public Transport Ticketing System Database Schema

-- Drop existing tables if they exist
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS tickets CASCADE;
DROP TABLE IF EXISTS trips CASCADE;
DROP TABLE IF EXISTS routes CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'PASSENGER',
    wallet_balance DECIMAL(10, 2) DEFAULT 100.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Routes table
CREATE TABLE routes (
    id SERIAL PRIMARY KEY,
    route_number VARCHAR(50) UNIQUE NOT NULL,
    origin VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    distance DECIMAL(10, 2),
    base_fare DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trips table
CREATE TABLE trips (
    id SERIAL PRIMARY KEY,
    route_id INT REFERENCES routes(id) ON DELETE CASCADE,
    departure_time TIMESTAMP NOT NULL,
    arrival_time TIMESTAMP NOT NULL,
    status VARCHAR(50) DEFAULT 'SCHEDULED',
    available_seats INT DEFAULT 50,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tickets table
CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    ticket_number VARCHAR(100) UNIQUE NOT NULL,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    trip_id INT REFERENCES trips(id) ON DELETE SET NULL,
    ticket_type VARCHAR(50) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'CREATED',
    purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    validated_at TIMESTAMP
);

-- Payments table
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    payment_id VARCHAR(100) UNIQUE NOT NULL,
    ticket_number VARCHAR(100) REFERENCES tickets(ticket_number) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    payment_method VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notifications table
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_tickets_user_id ON tickets(user_id);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_trips_route_id ON trips(route_id);
CREATE INDEX idx_trips_departure_time ON trips(departure_time);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);

-- Insert sample data

-- Sample users
INSERT INTO users (email, password_hash, full_name, role, wallet_balance) VALUES
('admin@transport.com', 'admin123', 'System Administrator', 'ADMIN', 10000.00),
('john.doe@email.com', 'password123', 'John Doe', 'PASSENGER', 500.00),
('jane.smith@email.com', 'password123', 'Jane Smith', 'PASSENGER', 300.00),
('validator1@transport.com', 'val123', 'Validator One', 'VALIDATOR', 0.00);

-- Sample routes
INSERT INTO routes (route_number, origin, destination, distance, base_fare) VALUES
('R001', 'Downtown', 'Airport', 25.5, 45.00),
('R002', 'Central Station', 'University', 12.3, 25.00),
('R003', 'Shopping Mall', 'Beach Front', 18.7, 35.00),
('R004', 'Industrial Area', 'Hospital', 8.2, 15.00),
('R005', 'North Terminal', 'South Terminal', 32.1, 55.00);

-- Sample trips for today and tomorrow
INSERT INTO trips (route_id, departure_time, arrival_time, status, available_seats) VALUES
(1, CURRENT_TIMESTAMP + INTERVAL '2 hours', CURRENT_TIMESTAMP + INTERVAL '3 hours', 'SCHEDULED', 45),
(1, CURRENT_TIMESTAMP + INTERVAL '4 hours', CURRENT_TIMESTAMP + INTERVAL '5 hours', 'SCHEDULED', 50),
(2, CURRENT_TIMESTAMP + INTERVAL '1 hour', CURRENT_TIMESTAMP + INTERVAL '1.5 hours', 'SCHEDULED', 48),
(2, CURRENT_TIMESTAMP + INTERVAL '3 hours', CURRENT_TIMESTAMP + INTERVAL '3.5 hours', 'SCHEDULED', 50),
(3, CURRENT_TIMESTAMP + INTERVAL '2.5 hours', CURRENT_TIMESTAMP + INTERVAL '3.5 hours', 'SCHEDULED', 42),
(4, CURRENT_TIMESTAMP + INTERVAL '1.5 hours', CURRENT_TIMESTAMP + INTERVAL '2 hours', 'SCHEDULED', 50),
(5, CURRENT_TIMESTAMP + INTERVAL '5 hours', CURRENT_TIMESTAMP + INTERVAL '7 hours', 'SCHEDULED', 38);

-- Sample tickets
INSERT INTO tickets (ticket_number, user_id, trip_id, ticket_type, amount, status, purchase_date) VALUES
('TKT-1001', 2, 1, 'SINGLE', 45.00, 'PAID', CURRENT_TIMESTAMP - INTERVAL '1 day'),
('TKT-1002', 3, 2, 'SINGLE', 25.00, 'PAID', CURRENT_TIMESTAMP - INTERVAL '2 hours'),
('TKT-1003', 2, 3, 'MULTIPLE', 70.00, 'VALIDATED', CURRENT_TIMESTAMP - INTERVAL '5 hours');

-- Sample payments
INSERT INTO payments (payment_id, ticket_number, user_id, amount, status, payment_method) VALUES
('PAY-1001', 'TKT-1001', 2, 45.00, 'SUCCESS', 'WALLET'),
('PAY-1002', 'TKT-1002', 3, 25.00, 'SUCCESS', 'CARD'),
('PAY-1003', 'TKT-1003', 2, 70.00, 'SUCCESS', 'WALLET');

-- Sample notifications
INSERT INTO notifications (user_id, message, notification_type, is_read) VALUES
(2, 'Your ticket TKT-1001 has been validated successfully', 'TICKET_VALIDATED', TRUE),
(3, 'Route R002 will have a 10-minute delay', 'SCHEDULE_UPDATE', FALSE),
(2, 'Thank you for using our transport system!', 'GENERAL', FALSE);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO transport_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO transport_user;

-- Display success message
DO $$
BEGIN
    RAISE NOTICE 'Database initialized successfully!';
    RAISE NOTICE 'Sample data inserted.';
END $$;