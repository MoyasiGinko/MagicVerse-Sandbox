# Quick Reference - Authentication System

## 🚀 Quick Start

### 1. Start Backend (Required)

```bash
cd backend-game-server
npm start
```

Backend must be running on `http://localhost:30820`

### 2. Open Godot Project

Game will automatically start with `AuthenticationEntry.tscn`

### 3. Test Flow

- **New Player:** Click Register tab, fill form, submit
- **Returning Player:** Game auto-loads splash screen if token exists
- **Error:** See error messages with guidance

## 📋 File Quick Reference

| File                      | Purpose                   | Type   |
| ------------------------- | ------------------------- | ------ |
| AuthenticationEntry.tscn  | Entry point router        | Scene  |
| AuthenticationScreen.tscn | Login/Register UI         | Scene  |
| SplashVerification.tscn   | Splash + Verify           | Scene  |
| AuthenticationManager.gd  | Backend communication     | Script |
| AuthenticationScreen.gd   | Form logic                | Script |
| SplashVerification.gd     | Splash logic              | Script |
| AuthenticationEntry.gd    | Router logic              | Script |
| Global.gd                 | (modified) Auth variables | Script |

## 🔑 Global Variables (After Login)

```gdscript
Global.auth_token          # JWT token (string)
Global.player_username     # Username (string)
Global.is_authenticated    # Boolean flag
```

## 🌐 API Endpoints (Backend)

```
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/verify
```

## ⚙️ Configuration Constants

### In `SplashVerification.gd`:

```gdscript
const MINIMUM_SPLASH_TIME: float = 15.0      # Splash duration
const BANNER_IMAGE_PATH: String = "res://title.png"
const VERIFICATION_TIMEOUT: float = 10.0     # Server response timeout
```

### In `AuthenticationManager.gd`:

```gdscript
var backend_url := "http://localhost:30820"  # Backend URL
const TOKEN_SAVE_PATH := "user://tinybox_token.json"
```

## 🔐 Input Validation Rules

| Field    | Rule                          | Error                   |
| -------- | ----------------------------- | ----------------------- |
| Username | 3-20 chars, alphanumeric + \_ | "Invalid username"      |
| Email    | Valid email format            | "Invalid email"         |
| Password | 8+ characters                 | "Password must be 8+"   |
| Confirm  | Match password                | "Passwords don't match" |

## 📊 Response Examples

### Successful Registration

```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": 1,
    "username": "player1",
    "email": "player@example.com",
    "created_at": "2026-01-08T12:00:00Z"
  }
}
```

### Successful Login

```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": 1,
    "username": "player1",
    "email": "player@example.com"
  }
}
```

### Token Verification Success

```json
{
  "valid": true,
  "user": {
    "id": 1,
    "username": "player1"
  }
}
```

### Token Verification Failed

```json
{
  "valid": false,
  "error": "Invalid token"
}
```

## 🎨 UI Elements

### AuthenticationScreen

- **Register Tab**

  - Username Input
  - Email Input
  - Password Input
  - Confirm Password Input
  - Status Label (error/success)
  - Register Button

- **Login Tab**
  - Username/Email Input
  - Password Input
  - Remember Me Checkbox
  - Status Label
  - Login Button

### SplashVerification

- **Banner Image** (fullscreen)
- **Loading Spinner** ("⏳ Verifying session...")
- **Progress Bar** (shows elapsed time)
- **Status Label** (detailed status)

## 🔄 Scene Transitions

```
AuthenticationEntry
├─ Has token? NO  → AuthenticationScreen
│
└─ Has token? YES → SplashVerification
                    ├─ Token valid? YES → MainScene.tscn
                    └─ Token valid? NO  → AuthenticationScreen
```

## 💾 Token Storage Location

```
user://tinybox_token.json
```

Format:

```json
{
  "token": "eyJ...",
  "username": "PlayerName",
  "timestamp": 1673456789
}
```

## 🔗 Integration with Multiplayer

In your WebSocket handshake:

```gdscript
var message = {
    "type": "handshake",
    "data": {
        "version": "0.4.0",
        "name": Global.player_username,    # ← From authentication
        "token": Global.auth_token         # ← From authentication
    }
}
```

## ❌ Common Issues

| Problem             | Solution                            |
| ------------------- | ----------------------------------- |
| "Connection failed" | Start backend: `npm start`          |
| Token not saving    | Check `user://` write permissions   |
| Banner not showing  | Ensure `res://title.png` exists     |
| "Username taken"    | Choose different username           |
| Loop back to login  | Token expired (7 days), login again |

## 📝 Logging & Debugging

Check console for:

- `Database connected at:` (backend startup)
- `authentication_complete` signal (successful login)
- `authentication_failed` signal (login error)
- `verification_complete` signal (token check result)

Enable debug in Godot:

```gdscript
print(Global.auth_token)        # Check token value
print(Global.player_username)   # Check username
print(Global.is_authenticated)  # Check auth status
```

## 🧪 Test Cases

### ✓ New User Registration

1. Start game
2. Click Register tab
3. Fill all fields
4. Click Register
5. Should see splash screen
6. Token saved to `user://tinybox_token.json`

### ✓ Existing User Login

1. Start game
2. Click Login tab
3. Enter credentials
4. Click Login
5. Should see splash screen
6. Token saved

### ✓ Returning Player (Auto-Login)

1. Play as new user (registers)
2. Close game
3. Reopen game
4. Should go directly to splash (no login screen)
5. Verify token in background
6. Proceed to MainScene

### ✓ Expired Token

1. Wait 7 days (or manually delete `user://tinybox_token.json`)
2. Start game
3. Should show login screen
4. Must login again with fresh credentials

### ✓ Wrong Credentials

1. Click Login tab
2. Enter wrong password
3. Click Login
4. Should show error message
5. Stay on login screen

## 🎯 Success Indicators

✅ Backend running (visible in terminal):

```
Server is running on port 30820
API endpoints available:
  - POST /api/auth/register
  - POST /api/auth/login
  - GET  /api/auth/verify
```

✅ Game starts (Godot console):

```
Game starting with AuthenticationEntry
```

✅ Successful auth:

- Token saved to `user://tinybox_token.json`
- Splash screen displays
- Auto-transitions to MainScene
- `Global.auth_token` is set
- `Global.player_username` is set

## 📚 Full Documentation

- **AUTHENTICATION.md** - Complete technical guide
- **AUTHENTICATION_ARCHITECTURE.md** - Visual diagrams & flows
- **backend-game-server/API_GUIDE.md** - Backend API reference

---

**Version:** 1.0
**Last Updated:** January 8, 2026
**Status:** ✅ Ready for Testing
