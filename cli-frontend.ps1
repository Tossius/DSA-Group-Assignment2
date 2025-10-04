# Smart Public Transport CLI Frontend
$baseUrl = "http://localhost"
$passengerPort = "9001"
$transportPort = "9002"

$currentUser = $null

function Show-MainMenu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "  Smart Public Transport Ticketing System" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($null -eq $currentUser) {
        Write-Host "1. Register" -ForegroundColor Green
        Write-Host "2. Login" -ForegroundColor Green
    } else {
        Write-Host "Logged in as: $($currentUser.name) ($($currentUser.email))" -ForegroundColor Yellow
        Write-Host "Wallet Balance: N`$$($currentUser.wallet_balance)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "3. View My Profile" -ForegroundColor Green
        Write-Host "4. View My Tickets" -ForegroundColor Green
        Write-Host "5. Browse Routes" -ForegroundColor Green
        Write-Host "6. Browse Trips" -ForegroundColor Green
        Write-Host "7. Logout" -ForegroundColor Red
    }
    Write-Host "0. Exit" -ForegroundColor Red
    Write-Host ""
}

function Register-User {
    Write-Host "`n=== User Registration ===" -ForegroundColor Cyan
    $email = Read-Host "Email"
    $password = Read-Host "Password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    $fullName = Read-Host "Full Name"
    
    try {
        $body = @{
            email = $email
            password = $passwordPlain
            full_name = $fullName
        } | ConvertTo-Json
        
        $uri = "${baseUrl}:${passengerPort}/passenger/register"
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body
        
        Write-Host "`nSuccess! $($response.message)" -ForegroundColor Green
        Write-Host "User ID: $($response.userId)" -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    catch {
        $errorMsg = $_.ErrorDetails.Message | ConvertFrom-Json
        Write-Host "`nError: $($errorMsg.error)" -ForegroundColor Red
        Write-Host "$($errorMsg.message)" -ForegroundColor Red
        Read-Host "`nPress Enter to continue"
    }
}

function Login-User {
    Write-Host "`n=== User Login ===" -ForegroundColor Cyan
    $email = Read-Host "Email"
    $password = Read-Host "Password" -AsSecureString
    $passwordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    
    try {
        $body = @{
            email = $email
            password = $passwordPlain
        } | ConvertTo-Json
        
        $uri = "${baseUrl}:${passengerPort}/passenger/login"
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body
        
        $script:currentUser = @{
            userId = $response.userId
            email = $email
            name = $response.name
            wallet_balance = $response.wallet_balance
        }
        
        Write-Host "`nWelcome back, $($response.name)!" -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    catch {
        $errorMsg = $_.ErrorDetails.Message | ConvertFrom-Json
        Write-Host "`nError: $($errorMsg.error)" -ForegroundColor Red
        Write-Host "$($errorMsg.message)" -ForegroundColor Red
        Read-Host "`nPress Enter to continue"
    }
}

function Show-Profile {
    Write-Host "`n=== Your Profile ===" -ForegroundColor Cyan
    try {
        $uri = "${baseUrl}:${passengerPort}/passenger/profile/$($currentUser.email)"
        $profile = Invoke-RestMethod -Uri $uri -Method Get
        
        Write-Host "Name: $($profile.name)" -ForegroundColor White
        Write-Host "Email: $($profile.email)" -ForegroundColor White
        Write-Host "Wallet Balance: N`$$($profile.wallet_balance)" -ForegroundColor Yellow
        
        # Update current user data
        $script:currentUser.wallet_balance = $profile.wallet_balance
    }
    catch {
        Write-Host "Error loading profile" -ForegroundColor Red
    }
    Read-Host "`nPress Enter to continue"
}

function Show-Tickets {
    Write-Host "`n=== Your Tickets ===" -ForegroundColor Cyan
    try {
        $uri = "${baseUrl}:${passengerPort}/passenger/tickets/$($currentUser.userId)"
        $tickets = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($tickets.Count -eq 0) {
            Write-Host "You have no tickets yet." -ForegroundColor Yellow
        } else {
            $tickets | Format-Table -Property ticket_number, ticket_type, amount, status, purchase_date -AutoSize
        }
    }
    catch {
        Write-Host "Error loading tickets" -ForegroundColor Red
    }
    Read-Host "`nPress Enter to continue"
}

function Show-Routes {
    Write-Host "`n=== Available Routes ===" -ForegroundColor Cyan
    try {
        $uri = "${baseUrl}:${transportPort}/transport/routes"
        $routes = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($routes.Count -eq 0) {
            Write-Host "No routes available." -ForegroundColor Yellow
        } else {
            $routes | Format-Table -Property id, name, route_code, start_location, end_location, distance_km -AutoSize
        }
    }
    catch {
        Write-Host "Error loading routes. Make sure TransportService is running." -ForegroundColor Red
    }
    Read-Host "`nPress Enter to continue"
}

function Show-Trips {
    Write-Host "`n=== Available Trips ===" -ForegroundColor Cyan
    try {
        $uri = "${baseUrl}:${transportPort}/transport/trips"
        $trips = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($trips.Count -eq 0) {
            Write-Host "No trips available." -ForegroundColor Yellow
        } else {
            $trips | Format-Table -Property id, trip_code, route_id, departure_time, vehicle_number, available_seats, base_fare, status -AutoSize
        }
    }
    catch {
        Write-Host "Error loading trips. Make sure TransportService is running." -ForegroundColor Red
    }
    Read-Host "`nPress Enter to continue"
}

# Main loop
while ($true) {
    Show-MainMenu
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" { if ($null -eq $currentUser) { Register-User } }
        "2" { if ($null -eq $currentUser) { Login-User } }
        "3" { if ($null -ne $currentUser) { Show-Profile } }
        "4" { if ($null -ne $currentUser) { Show-Tickets } }
        "5" { if ($null -ne $currentUser) { Show-Routes } }
        "6" { if ($null -ne $currentUser) { Show-Trips } }
        "7" { 
            if ($null -ne $currentUser) { 
                $script:currentUser = $null
                Write-Host "`nLogged out successfully!" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
        }
        "0" { 
            Write-Host "`nThank you for using Smart Public Transport!" -ForegroundColor Cyan
            exit 
        }
        default { 
            Write-Host "`nInvalid option!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}