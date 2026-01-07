# Authentication System Documentation

## Overview

The authentication system handles user registration, login, and verification before entering the main game. It includes:

1. **AuthenticationScreen.tscn** - Registration/Login UI
2. **SplashVerification.tscn** - Verification + Splash screen
3. **AuthenticationManager.gd** - Backend communication
4. **AuthenticationEntry.gd** - Entry point routing

## Flow Diagram

```
Game Start
    ↓
AuthenticationEntry.tscn
    ↓
    ├─ Has saved token?
    │   ├─ YES → SplashVerification.tscn (verify token)
    │   └─ NO → AuthenticationScreen.tscn
    ↓
    ├─ Token valid?
    │   ├─ YES → Continue to MainScene.tscn
    │   └─ NO → Return to AuthenticationScreen.tscn
```

## Scene Files

### 1. AuthenticationEntry.tscn

**Location:** `res://data/scene/AuthenticationEntry.tscn`

**Purpose:** Entry point that checks for existing saved token.

**Logic:**

- On game start, checks if user has a saved JWT token
- If token exists → routes to SplashVerification
- If no token → routes to AuthenticationScreen

### 2. AuthenticationScreen.tscn

**Location:** `res://data/scene/AuthenticationScreen.tscn`

**Purpose:** Registration and login interface.

**Features:**

- Two tabs: Register and Login
- Register form requires:
  - Username (3-20 chars, alphanumeric + underscore)
  - Email (valid email format)
  - Password (minimum 8 characters)
  - Password confirmation
- Login form requires:
  - Username or Email
  - Password
  - Optional "Remember me" checkbox (saves token locally)

**Script:** `res://src/AuthenticationScreen.gd`

### 3. SplashVerification.tscn

**Location:** `res://data/scene/SplashVerification.tscn`

**Purpose:** Shows fullscreen banner while verifying session.

**Features:**

- Displays fullscreen banner image (from `res://title.png`)
- Shows verification progress
- Minimum display time: 15 seconds
- Verifies JWT token validity during splash display
- Auto-advances to game if token is valid
- Returns to login if token is expired/invalid

**Script:** `res://src/SplashVerification.gd`

## GDScript Files

### AuthenticationManager.gd

**Location:** `res://src/AuthenticationManager.gd`

**Public Methods:**

```gdscript
# Register new user
register_user(username: String, email: String, password: String) -> void

# Login existing user
login_user(username: String, password: String) -> void

# Verify JWT token
verify_token(token: String) -> void

# Load saved token from disk
load_saved_token() -> String

# Save token to disk
save_token(token: String, username: String) -> void

# Clear saved token
clear_saved_token() -> void
```

**Signals:**

```gdscript
authentication_complete(token: String, username: String)
authentication_failed(reason: String)
verification_complete(is_valid: bool)
```

**Token Storage:**

- Tokens are saved to `user://tinybox_token.json`
- Also stored in `Global.auth_token`
- Username stored in `Global.player_username`

### AuthenticationScreen.gd

**Location:** `res://src/AuthenticationScreen.gd`

**Handles:**

- Registration form validation
- Login form validation
- Error display
- Form state management
- Transition to splash screen

### SplashVerification.gd

**Location:** `res://src/SplashVerification.gd`

**Features:**

- Minimum 15-second splash display
- Parallel verification with backend
- Progress bar showing elapsed time
- Auto-transitions based on verification result
- Graceful fallback on timeout

## Backend Integration

### API Endpoints Used

```
POST /api/auth/register
  Request: { username, email, password }
  Response: { token, user: { id, username, email, created_at } }

POST /api/auth/login
  Request: { username, password }
  Response: { token, user: { id, username, email } }

GET /api/auth/verify
  Headers: Authorization: Bearer {token}
  Response: { valid: bool, user: { id, username } }
```

### Backend Requirements

Make sure the backend server is running on `http://localhost:30820`:

```bash
cd backend-game-server
npm start
```

## Global Variables

The following properties are added to `Global.gd`:

```gdscript
var auth_token: String = ""           # JWT token
var player_username: String = ""      # Logged-in username
var is_authenticated: bool = false    # Auth status flag
```

## Configuration

### Splash Screen Duration

Edit `SplashVerification.gd`:

```gdscript
const MINIMUM_SPLASH_TIME: float = 15.0  # Change this value
```

### Banner Image

By default uses `res://title.png`. To change:

```gdscript
const BANNER_IMAGE_PATH: String = "res://your_banner.png"
```

### Backend URL

Edit `AuthenticationManager.gd`:

```gdscript
var backend_url := "http://localhost:30820"
```

### Verification Timeout

Edit `SplashVerification.gd`:

```gdscript
const VERIFICATION_TIMEOUT: float = 10.0  # seconds
```

## Error Handling

### Registration Errors

- Username too short/long
- Username contains invalid characters
- Email invalid format
- Password less than 8 characters
- Username already taken
- Email already registered
- Connection to backend failed

### Login Errors

- Invalid username/password combination
- User account doesn't exist
- Backend connection failed

### Verification Errors

- Token expired (returns to login)
- Invalid token (returns to login)
- Backend unreachable (timeout after 10s, returns to login)

## Security Features

1. **Password Security:**

   - Minimum 8 characters
   - Hashed with bcrypt on backend
   - Never transmitted in plain text
   - Cleared from memory after use

2. **Token Management:**

   - JWT tokens stored locally
   - 7-day expiration
   - Verified on startup
   - Can be manually cleared

3. **Input Validation:**

   - Username format validation
   - Email format validation
   - Client-side checks before sending

4. **Local Storage:**
   - Tokens saved in `user://` directory
   - User-specific encrypted by OS

## Usage Example

### For Players

1. **First time:**

   - Game opens → AuthenticationEntry checks for token
   - No token found → AuthenticationScreen opens
   - Player fills register form or login tab
   - Backend creates account / verifies credentials
   - SplashVerification shows while banner displays (15 seconds)
   - Token verified in background
   - Game proceeds to MainScene.tscn

2. **Returning player (with saved token):**

   - Game opens → AuthenticationEntry checks for token
   - Token found → SplashVerification opens directly
   - Token verified with backend during splash
   - If valid → Game proceeds
   - If invalid → Returns to AuthenticationScreen

3. **Token expired:**
   - SplashVerification detects invalid token
   - Returns to AuthenticationScreen
   - Displays "Session expired, please login again"
   - Player logs in again with fresh token

### For Developers

```gdscript
# Access authenticated user info anywhere:
print(Global.auth_token)      # JWT token
print(Global.player_username)  # Username
print(Global.is_authenticated) # Boolean flag

# Manually check authentication:
var auth_manager = AuthenticationManager.new()
var is_valid = await auth_manager.verify_token(Global.auth_token)

# Clear authentication:
auth_manager.clear_saved_token()
```

## Troubleshooting

### "Connection failed" error

- Check if backend server is running: `npm start` in `backend-game-server/`
- Verify server is on port 30820
- Check `AuthenticationManager.gd` backend_url setting

### "Username already taken" error

- Choose a different username
- Username must be unique across all players

### "Session expired" on splash screen

- Token is older than 7 days
- Need to login again with fresh credentials
- This is expected behavior

### Banner image not showing

- Check if `res://title.png` exists
- Verify image path in `SplashVerification.gd`
- Image will fail gracefully if not found

### Token not saving

- Check user:// directory permissions
- Ensure `tinybox_token.json` can be written
- Check disk space available

## File Locations Summary

```
res://data/scene/
  ├── AuthenticationEntry.tscn      # Entry point
  ├── AuthenticationScreen.tscn      # Login/Register UI
  └── SplashVerification.tscn        # Splash + Verification

res://src/
  ├── AuthenticationManager.gd       # Backend communication
  ├── AuthenticationScreen.gd        # Login/Register logic
  ├── SplashVerification.gd          # Splash logic
  ├── AuthenticationEntry.gd         # Entry routing
  └── Global.gd                      # (updated with auth vars)

user://
  └── tinybox_token.json             # Saved token (created at runtime)
```

## Next Steps

1. ✅ Authentication system created
2. ✅ Token storage implemented
3. ✅ Backend verification integrated
4. 🔄 Test with backend server running
5. 🔄 Integrate with multiplayer menu (pass token to WebSocket)
6. 🔄 Add user profile display with stats

## Testing Checklist

- [ ] Backend server running on port 30820
- [ ] Register new account successfully
- [ ] Login with registered account
- [ ] Token saves to disk
- [ ] Splash screen displays for 15+ seconds
- [ ] Token verifies correctly
- [ ] Game proceeds to MainScene
- [ ] Returning player skips login (uses saved token)
- [ ] Expired token returns to login
- [ ] Error messages display correctly
