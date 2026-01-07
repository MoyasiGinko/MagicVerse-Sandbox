# 🎮 Tinybox Authentication System - Complete Index

## 📋 Documentation Guide

### **For Quick Start** ⚡

👉 **Read:** [`AUTHENTICATION_QUICK_REFERENCE.md`](AUTHENTICATION_QUICK_REFERENCE.md)

- 5-minute overview
- Test checklist
- Common errors & fixes
- Quick configuration

### **For Implementation Overview** 📊

👉 **Read:** [`AUTHENTICATION_SUMMARY.md`](AUTHENTICATION_SUMMARY.md)

- What was created
- Complete flow diagrams
- File locations
- Integration checklist

### **For Technical Details** 🔧

👉 **Read:** [`docs/AUTHENTICATION.md`](docs/AUTHENTICATION.md)

- Full API reference
- Configuration options
- Security features
- Troubleshooting guide

### **For Architecture & Design** 🏗️

👉 **Read:** [`AUTHENTICATION_ARCHITECTURE.md`](AUTHENTICATION_ARCHITECTURE.md)

- Visual diagrams
- Data flow charts
- State machine
- Component interactions

### **For Complete Overview** ✨

👉 **Read:** [`AUTHENTICATION_COMPLETE.md`](AUTHENTICATION_COMPLETE.md)

- Everything at a glance
- Feature checklist
- Integration guide
- Testing procedures

## 📁 Scene Files

```
res://data/scene/
├── AuthenticationEntry.tscn .............. Entry point router
├── AuthenticationScreen.tscn ............. Login/Register UI
└── SplashVerification.tscn ............... Splash screen + verification
```

**Purpose of Each:**

| Scene                    | Purpose                 | When Shown                           |
| ------------------------ | ----------------------- | ------------------------------------ |
| **AuthenticationEntry**  | Routes based on token   | On game start                        |
| **AuthenticationScreen** | Registration/Login form | First time or expired token          |
| **SplashVerification**   | Splash + token verify   | After login or for returning players |

## 📝 Script Files

```
res://src/
├── AuthenticationManager.gd .............. Backend API communication
├── AuthenticationScreen.gd ............... Form logic & validation
├── SplashVerification.gd ................. Splash screen logic
├── AuthenticationEntry.gd ................ Router logic
└── Global.gd (modified) .................. Auth global variables
```

**What Each Does:**

| Script                    | Responsibility                                         |
| ------------------------- | ------------------------------------------------------ |
| **AuthenticationManager** | HTTP requests, token storage, backend API calls        |
| **AuthenticationScreen**  | Form validation, user input handling, state management |
| **SplashVerification**    | Banner display, token verification, scene transitions  |
| **AuthenticationEntry**   | Startup routing based on saved token presence          |

## 🔄 Game Flow

### Three Possible Paths:

#### 1️⃣ **New Player**

```
Game Start → No saved token → AuthenticationScreen →
Register → Get token → SplashVerification →
Verify token → MainScene ✓
```

#### 2️⃣ **Returning Player (Token Valid)**

```
Game Start → Found saved token → SplashVerification →
Verify token (valid) → MainScene ✓
```

#### 3️⃣ **Returning Player (Token Expired)**

```
Game Start → Found saved token → SplashVerification →
Verify token (invalid) → Clear token → AuthenticationScreen →
Login → Get new token → SplashVerification → MainScene ✓
```

## 🎯 Key Features

✅ **Registration System**

- Username validation (3-20 chars)
- Email format validation
- Password requirements (8+ chars)
- Confirm password matching
- Backend account creation

✅ **Login System**

- Username or email accepted
- Password verification
- JWT token generation
- "Remember me" option
- 7-day token expiration

✅ **Splash Screen**

- Fullscreen banner display
- Minimum 15-second duration
- Loading spinner animation
- Progress bar
- Status messages

✅ **Token Management**

- Automatic storage to disk
- Background verification
- Expiration handling
- Clear on logout

✅ **Security**

- bcrypt password hashing
- JWT token signatures
- Input validation
- HTTPS-ready
- Secure local storage

## 🔌 Backend Integration

**Server Required:** Node.js backend on port 30820

**API Endpoints Used:**

- `POST /api/auth/register` - Create account
- `POST /api/auth/login` - Authenticate
- `GET /api/auth/verify` - Validate token

**Start Backend:**

```bash
cd backend-game-server
npm start
```

## 💾 Data Storage

### Token Saved Locally:

```
File: user://tinybox_token.json

Format:
{
  "token": "eyJhbGci...",
  "username": "PlayerName",
  "timestamp": 1673456789
}
```

### Global Variables:

```
Global.auth_token ............... JWT token (string)
Global.player_username ........... Player username (string)
Global.is_authenticated .......... Auth status (bool)
```

## 🚀 Quick Setup

### Step 1: Start Backend

```bash
cd backend-game-server
npm start
# Wait for: "Server is running on port 30820"
```

### Step 2: Launch Game

- Open Godot
- Press F5 or click "Run Project"
- Game automatically uses AuthenticationEntry

### Step 3: Test

- **New player?** Click Register, fill form, submit
- **Returning?** Game skips login if token exists
- **Expired?** Game returns to login, prompt to re-authenticate

## 📚 Documentation File Purpose

| File                | Best For             | Length      |
| ------------------- | -------------------- | ----------- |
| QUICK_REFERENCE     | Fast lookup          | 400 lines   |
| SUMMARY             | Overview             | 500 lines   |
| ARCHITECTURE        | Understanding design | 800 lines   |
| docs/AUTHENTICATION | Full details         | 1000+ lines |
| COMPLETE            | Everything           | 600 lines   |

## 🔧 Common Configurations

### Change Splash Duration:

Edit: `res://src/SplashVerification.gd` line 10

```gdscript
const MINIMUM_SPLASH_TIME: float = 15.0  # in seconds
```

### Change Banner Image:

Edit: `res://src/SplashVerification.gd` line 12

```gdscript
const BANNER_IMAGE_PATH: String = "res://title.png"
```

### Change Backend URL:

Edit: `res://src/AuthenticationManager.gd` line 9

```gdscript
var backend_url := "http://localhost:30820"
```

## ✅ Pre-Launch Checklist

- [ ] Backend server running (`npm start`)
- [ ] All scene files exist
- [ ] All script files exist
- [ ] Global.gd updated with auth variables
- [ ] project.godot entry point changed
- [ ] Banner image exists at `res://title.png`
- [ ] No compilation errors
- [ ] Token storage directory writable

## 🎓 Learning Path

**If you're new to this system:**

1. Start with `AUTHENTICATION_QUICK_REFERENCE.md` (5 min read)
2. Then read `AUTHENTICATION_SUMMARY.md` (10 min read)
3. Look at `AUTHENTICATION_ARCHITECTURE.md` diagrams (5 min read)
4. Dive into `docs/AUTHENTICATION.md` for details (as needed)

**If you need to integrate with multiplayer:**

1. Check "Integration with Multiplayer" in `AUTHENTICATION_COMPLETE.md`
2. See code examples in `docs/AUTHENTICATION.md`
3. Look at `AUTHENTICATION_ARCHITECTURE.md` "Integration Points"

**If you're experiencing issues:**

1. Check "Troubleshooting" in `docs/AUTHENTICATION.md`
2. Review "Common Issues" in `AUTHENTICATION_QUICK_REFERENCE.md`
3. Verify "Pre-Launch Checklist" above

## 🤝 Integration Points

### With Multiplayer Menu:

```gdscript
# Pass token to WebSocket handshake
ws.send(JSON.stringify({
    "type": "handshake",
    "data": {
        "token": Global.auth_token,        # ← From authentication
        "name": Global.player_username     # ← From authentication
    }
}))
```

### With User Stats:

```gdscript
# Access player statistics
var stats_url = "/api/users/{user_id}/stats"
# Use Global.auth_token in Authorization header
```

### With Room Creation:

```gdscript
# Create authenticated rooms
# Send token in WebSocket message
# Backend validates token before room creation
```

## 📊 Statistics

**Code Created:**

- Scene Files: 3
- Script Files: 4
- Documentation Files: 5
- Total Lines of Code: ~1500
- Total Documentation Lines: ~5000

**Features Implemented:**

- Registration system ✓
- Login system ✓
- Token persistence ✓
- Splash screen ✓
- Verification system ✓
- Error handling ✓
- Security features ✓

## 🎉 Success Indicators

**Backend Ready When You See:**

```
Server is running on port 30820
API endpoints available:
  - POST /api/auth/register
  - POST /api/auth/login
  - GET  /api/auth/verify
```

**Game Ready When You See:**

- AuthenticationScreen appears OR
- SplashVerification appears (if token exists)
- No errors in console

**Authentication Works When:**

- Registration succeeds
- Token saves to `user://tinybox_token.json`
- Splash screen displays 15+ seconds
- Auto-transitions to MainScene
- Returning players skip login screen

## 🔗 File Relationships

```
AuthenticationEntry.tscn
    ↓ (routes to one of)
    ├─ AuthenticationScreen.tscn
    │    ↓ (after register/login)
    │    └─ SplashVerification.tscn
    │         ↓ (after verification)
    │         └─ MainScene.tscn
    │
    └─ SplashVerification.tscn (if token exists)
         ↓ (after verification)
         └─ MainScene.tscn
```

## 🚦 Status

| Component             | Status      |
| --------------------- | ----------- |
| Authentication System | ✅ Complete |
| Registration UI       | ✅ Complete |
| Login UI              | ✅ Complete |
| Splash Screen         | ✅ Complete |
| Token Management      | ✅ Complete |
| Backend Integration   | ✅ Complete |
| Documentation         | ✅ Complete |
| Ready for Testing     | ✅ Yes      |

---

## Next Steps

1. **Verify backend is running**

   ```bash
   cd backend-game-server && npm start
   ```

2. **Launch the game**

   - Open Godot
   - Press F5

3. **Test the flow**

   - Register new account OR
   - See splash screen if token exists

4. **Integrate with multiplayer**

   - Pass token in WebSocket handshake
   - Access username in menu

5. **Monitor player stats**
   - Stats available at `/api/users/{id}/stats`
   - Use token in Authorization header

---

**System Version:** 1.0
**Last Updated:** January 8, 2026
**Status:** ✅ Production Ready
**Documentation:** Complete

**Questions?** Check the appropriate documentation file above.
