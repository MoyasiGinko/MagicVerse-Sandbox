# Authentication System - Implementation Summary

## ✅ What's Been Created

### 1. **AuthenticationManager.gd** (Backend Communication)

- Handles HTTP requests to backend server
- Manages JWT tokens (save, load, verify, clear)
- Validates user inputs before submission
- Emits signals for success/failure
- Stores tokens in `user://tinybox_token.json`

### 2. **AuthenticationScreen.tscn + GDScript** (Login/Register UI)

Two-tab interface:

- **Register tab:** Username, Email, Password, Confirm Password
- **Login tab:** Username/Email, Password, "Remember me" checkbox

Features:

- Real-time form validation
- Error message display
- Loading states on buttons
- Smooth transitions to splash screen

### 3. **SplashVerification.tscn + GDScript** (Splash + Verification)

Full-screen splash screen that:

- Displays banner image (`res://title.png`) fullscreen
- Shows minimum 15-second display time
- Verifies JWT token in parallel
- Shows progress bar and status updates
- Auto-advances if verification succeeds
- Returns to login if token is invalid/expired

### 4. **AuthenticationEntry.tscn + GDScript** (Entry Point Router)

Smart routing that:

- Checks for saved token on startup
- Routes to splash screen if token exists
- Routes to login screen if no token
- Enables seamless returning player experience

### 5. **Updated Global.gd**

Added authentication properties:

- `auth_token: String` - Stores JWT token
- `player_username: String` - Stores logged-in player's username
- `is_authenticated: bool` - Authentication status flag

### 6. **Updated project.godot**

Changed main scene to `res://data/scene/AuthenticationEntry.tscn`

## 🔄 Complete Authentication Flow

### New Player

```
Game Start
  ↓
AuthenticationEntry checks for saved token (none)
  ↓
AuthenticationScreen shows (Register tab visible)
  ↓
Player fills: username, email, password, confirm
  ↓
Clicks "Register" button
  ↓
AuthenticationManager sends POST to /api/auth/register
  ↓
Backend creates user, returns JWT token
  ↓
Token saved to user://tinybox_token.json
  ↓
SplashVerification scene loads
  ↓
Banner displays for minimum 15 seconds
  ↓
During banner: AuthenticationManager verifies token with /api/auth/verify
  ↓
If valid → Auto-transitions to MainScene.tscn
  ↓
Player can now access multiplayer menu
```

### Returning Player

```
Game Start
  ↓
AuthenticationEntry checks for saved token (found)
  ↓
SplashVerification scene loads directly
  ↓
Banner displays for minimum 15 seconds
  ↓
AuthenticationManager verifies saved token with /api/auth/verify
  ↓
If valid → Auto-transitions to MainScene.tscn
  ↓
If invalid → Back to AuthenticationScreen (shows "Please login again")
  ↓
Player logs in with fresh credentials
```

### Token Expired

```
SplashVerification during verification
  ↓
Token verification fails (expired or invalid)
  ↓
Goes back to AuthenticationScreen
  ↓
Shows message "Session expired, please login again"
  ↓
Player logs in with password
  ↓
Fresh token obtained, process continues
```

## 📁 File Locations

```
res://data/scene/
  ├── AuthenticationEntry.tscn          ← Game entry point
  ├── AuthenticationScreen.tscn          ← Login/Register UI
  └── SplashVerification.tscn            ← Splash + Verification

res://src/
  ├── AuthenticationManager.gd           ← Backend communication
  ├── AuthenticationScreen.gd            ← Login/Register logic
  ├── SplashVerification.gd              ← Splash logic
  ├── AuthenticationEntry.gd             ← Entry routing
  └── Global.gd                          ← (Modified: added auth vars)

res://docs/
  └── AUTHENTICATION.md                  ← Full documentation

user://
  └── tinybox_token.json                 ← Token storage (at runtime)
```

## 🔌 Backend Integration

**Backend must be running:**

```bash
cd backend-game-server
npm start
```

**API Endpoints Used:**

- `POST /api/auth/register` - Create account
- `POST /api/auth/login` - Authenticate user
- `GET /api/auth/verify` - Validate token

**Configuration:**

- Backend URL: `http://localhost:30820` (in AuthenticationManager.gd)
- Can be changed to any backend endpoint

## ⚙️ Configuration Options

### Splash Screen Duration

`SplashVerification.gd` line ~10:

```gdscript
const MINIMUM_SPLASH_TIME: float = 15.0  # Change to desired seconds
```

### Banner Image

`SplashVerification.gd` line ~12:

```gdscript
const BANNER_IMAGE_PATH: String = "res://title.png"  # Change image path
```

### Verification Timeout

`SplashVerification.gd` line ~13:

```gdscript
const VERIFICATION_TIMEOUT: float = 10.0  # Max wait for server response
```

## 🔐 Security Features

✅ **Password Security:**

- Minimum 8 characters enforced
- Hashed with bcrypt on backend
- Cleared from memory after use

✅ **Token Management:**

- JWT tokens with 7-day expiration
- Verified on every startup
- Saved in OS-protected user:// directory

✅ **Input Validation:**

- Username: 3-20 chars, alphanumeric + underscore
- Email: valid email format required
- Password: minimum 8 characters

✅ **Backend Communication:**

- HTTPS-ready (switch to https:// when deployed)
- Parameterized queries (no SQL injection)
- Token-based authentication

## 📊 Data Stored Locally

In `user://tinybox_token.json`:

```json
{
  "token": "eyJhbGc...",
  "username": "PlayerName",
  "timestamp": 1673456789
}
```

Accessible via:

- `Global.auth_token` - JWT token
- `Global.player_username` - Player's username
- `Global.is_authenticated` - Boolean flag

## 🚀 How to Test

### 1. Start Backend

```bash
cd backend-game-server
npm start
```

### 2. Launch Game

Open Godot and run the project. AuthenticationEntry will be the first scene.

### 3. Register New Account

- Click "Register" tab
- Fill in username (e.g., "testplayer")
- Fill in email (e.g., "test@example.com")
- Password (8+ chars)
- Click "Register"

### 4. See Splash Screen

- After registration, splash screen appears
- Banner displays for 15 seconds minimum
- Token verifies during splash
- Auto-transitions to main game

### 5. Test Returning Player

- Close and restart game
- Splash screen appears immediately (uses saved token)
- No login needed if token is still valid

### 6. Test Token Expiration

- Wait 7 days or manually delete `user://tinybox_token.json`
- Game will ask to login again

## 📝 Usage in Multiplayer Menu

When using the global mode multiplayer, pass the token to WebSocket:

```gdscript
# In MultiplayerNodeAdapter.gd or your WebSocket handler:
var token = Global.auth_token
var username = Global.player_username

ws.send(JSON.stringify({
    "type": "handshake",
    "data": {
        "version": "0.4.0",
        "name": username,
        "token": token  # ← This is now available!
    }
}))
```

## ✨ Enhancements for Future

- [ ] Password reset via email
- [ ] Two-factor authentication
- [ ] Social login (Discord, Google, etc.)
- [ ] User profile customization
- [ ] Avatar upload
- [ ] Friend system
- [ ] Account settings/preferences
- [ ] Session management (logout, multiple devices)

## 🐛 Troubleshooting

| Issue                    | Solution                                          |
| ------------------------ | ------------------------------------------------- |
| "Connection failed"      | Start backend: `npm start` in backend-game-server |
| "Username already taken" | Choose different username                         |
| Token not saving         | Check `user://` directory permissions             |
| Banner not showing       | Verify `res://title.png` exists                   |
| "Session expired"        | Normal - token is older than 7 days, login again  |

## 📞 Integration Checklist

- [x] AuthenticationManager created
- [x] AuthenticationScreen UI created
- [x] SplashVerification splash screen created
- [x] AuthenticationEntry router created
- [x] Global variables added
- [x] Project entry point updated
- [ ] Test with running backend
- [ ] Test registration flow
- [ ] Test login flow
- [ ] Test token persistence
- [ ] Integrate token into multiplayer menu
- [ ] Test global mode with authentication

---

**Status:** ✅ Ready for testing with backend server

**Next Step:** Run backend server and test the complete authentication flow
