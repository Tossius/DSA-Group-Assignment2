@echo off
echo Testing Admin Service...
echo.

REM Set the base URL
set BASE_URL=http://localhost:9096/admin

REM Test 1: Health Check
echo 1. Testing Health Check...
curl -X GET %BASE_URL%/health
echo.
echo.

REM Test 2: Get Routes
echo 2. Getting existing routes...
curl -X GET %BASE_URL%/routes
echo.
echo.

REM Test 3: Create a new route
echo 3. Creating a new route...
curl -X POST %BASE_URL%/routes ^
  -H "Content-Type: application/json" ^
  -d "{\"name\": \"Test Route\", \"routeCode\": \"TEST001\", \"startLocation\": \"Test Start\", \"endLocation\": \"Test End\", \"distanceKm\": 25.0, \"estimatedDurationMinutes\": 35}"
echo.
echo.

REM Test 4: Get reports
echo 4. Testing ticket sales report...
curl -X GET %BASE_URL%/reports/ticketSales
echo.
echo.

echo 5. Testing passenger traffic report...
curl -X GET %BASE_URL%/reports/passengerTraffic
echo.
echo.

echo Testing completed!
pause

