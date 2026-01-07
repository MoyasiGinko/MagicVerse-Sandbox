# Authentication System - Visual Architecture

## Scene Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                        Game Startup                              │
│                     (AuthenticationEntry)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    Check saved token?
                             │
                ┌────────────┴────────────┐
                │                         │
                YES                       NO
                │                         │
                ▼                         ▼
    ┌───────────────────────┐  ┌──────────────────────────┐
    │  SplashVerification   │  │ AuthenticationScreen     │
    │   (Verify Token)      │  │ (Register / Login)       │
    │  (Show Banner 15s)    │  │                          │
    └───────────┬───────────┘  └──────────┬───────────────┘
                │                         │
                │                    User submits
                │                         │
                ▼                         ▼
         Token Valid?          ┌──────────────────────┐
                │              │ AuthenticationManager│
                │              │  POST /api/auth/*    │
         ┌──────┴──────┐       │                      │
         │             │       └──────────┬───────────┘
         YES           NO                 │
         │             │                  ▼
         │             │        Account created /
         │             │        User authenticated
         │             │                 │
         │             │        Save token locally
         │             │                 │
         │             ▼                 ▼
         │      ┌─────────────┐   ┌──────────────┐
         │      │ AuthScreen  │   │ Splash Screen│
         │      │ (Show error)│   │  (Verify)    │
         │      │ (Keep open) │   │              │
         │      └─────────────┘   └──────┬───────┘
         │                              │
         └──────────────┬───────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │    MainScene.tscn                │
         │  (Main Game / Menu)              │
         │                                  │
         │  ✓ Token in Global.auth_token    │
         │  ✓ Username in Global.player     │
         │  ✓ Ready for multiplayer         │
         └──────────────────────────────────┘
```

## Component Interactions

```
┌──────────────────────────────────────────────────────────────────┐
│                    Godot Client                                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────────────┐        ┌──────────────────────────┐    │
│  │ Authentication     │        │ Splash Verification      │    │
│  │ Screen             │        │ Scene                    │    │
│  │                    │        │                          │    │
│  │ - Register Form    │        │ - Banner Display (15s)   │    │
│  │ - Login Form       │        │ - Progress Bar           │    │
│  │ - Input Validation │        │ - Status Updates         │    │
│  └────────┬───────────┘        └────────┬─────────────────┘    │
│           │                             │                      │
│           └─────────────┬───────────────┘                       │
│                         │                                       │
│               ┌─────────▼────────┐                              │
│               │ Authentication   │                              │
│               │ Manager          │                              │
│               │                  │                              │
│               │ - HTTP Requests  │                              │
│               │ - Token Storage  │                              │
│               │ - Signal Emitting│                              │
│               └─────────┬────────┘                              │
│                         │                                       │
│                         │ (HTTP)                                │
│                         │                                       │
└─────────────────────────┼──────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│              Backend Server (Node.js)                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────────────┐      ┌──────────────────────────┐      │
│  │ Auth Routes        │      │ SQLite Database          │      │
│  │                    │      │                          │      │
│  │ POST /register     │◄────►│ - users table            │      │
│  │ POST /login        │      │ - player_stats table     │      │
│  │ GET /verify        │      │ - rooms table            │      │
│  │                    │      │ - match_history table    │      │
│  │ Validations:       │      │                          │      │
│  │ - Password hash    │      │ JWT Secret (env var)     │      │
│  │ - Username/Email   │      │                          │      │
│  │ - Token generation │      │                          │      │
│  └────────────────────┘      └──────────────────────────┘      │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Data Flow: Registration

```
User Input
    │
    ▼
┌─────────────────────────┐
│ AuthenticationScreen    │
│ _on_register_pressed()  │
└────────────┬────────────┘
             │
             ▼
    ┌────────────────────┐
    │ Validate Input     │
    │ - Username (3-20)  │
    │ - Email format     │
    │ - Password (8+)    │
    │ - Confirm match    │
    └────────┬───────────┘
             │
             ▼
┌─────────────────────────────────┐
│ AuthenticationManager            │
│ register_user()                 │
└────────────┬────────────────────┘
             │
             ▼
     ┌───────────────────┐
     │ Create HTTP Client│
     │ Connect to :30820 │
     └────────┬──────────┘
              │
              ▼
      ┌──────────────────────┐
      │ POST /api/auth/register
      │ { username, email,   │
      │   password }         │
      └────────┬─────────────┘
               │
               ▼
         ┌──────────────────┐
         │ Backend Server   │
         │ - Hash password  │
         │ - Create user    │
         │ - Generate JWT   │
         │ - Create stats   │
         └────────┬─────────┘
                  │
                  ▼
          ┌──────────────┐
          │ Response:    │
          │ {            │
          │  token: "...",
          │  user: {...} │
          │ }            │
          └────────┬─────┘
                   │
                   ▼
        ┌───────────────────────┐
        │ AuthenticationManager  │
        │ Save token locally     │
        │ - user://tinybox*.json │
        │ - Global.auth_token    │
        │ - Global.player_username
        └────────┬──────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ authentication_complete     │
   │ (token, username)           │
   └────────┬────────────────────┘
            │
            ▼
   ┌─────────────────────────────┐
   │ AuthenticationScreen         │
   │ _on_authentication_complete()│
   │ - Clear passwords            │
   │ - Show "Loading..." message  │
   │ - Wait 1 second              │
   └────────┬────────────────────┘
            │
            ▼
   ┌─────────────────────────────┐
   │ Change Scene to              │
   │ SplashVerification.tscn      │
   └─────────────────────────────┘
```

## Data Flow: Token Verification

```
SplashVerification._ready()
         │
         ▼
┌──────────────────────────┐
│ Load Saved Token         │
│ user://tinybox_token.json│
└────────┬─────────────────┘
         │
         ├─────────────────────┬─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
    Token Found          No Token              (Setup Display)
         │                   │                     │
         │                   │                ┌────▼──────┐
         │                   │                │ Show      │
         │                   │                │ Banner    │
         │                   │                │ 15+ secs  │
         │                   │                └───────────┘
         │                   │
         ▼                   ▼
    ┌─────────────┐   ┌──────────────┐
    │ Verify Token│   │ No Session   │
    │ with Backend│   │ Go to Login   │
    └─────┬───────┘   └──────────────┘
          │
    ┌─────▼──────────────────────────┐
    │ GET /api/auth/verify            │
    │ Headers: Authorization: Bearer..│
    └─────┬──────────────────────────┘
          │
          ▼
    ┌────────────────┐
    │ Backend Check  │
    │ - Verify JWT   │
    │ - Check expiry │
    │ - Get user     │
    └────────┬───────┘
             │
        ┌────┴─────┐
        │           │
        ▼           ▼
    Valid        Invalid
      │             │
      │             ▼
      │      ┌──────────────┐
      │      │ Response:    │
      │      │ {            │
      │      │  "valid":false
      │      │ }            │
      │      └────┬─────────┘
      │           │
      ▼           ▼
  (continues    Clear Token
   loading)     Go to Login
      │
      ▼
  ┌────────────────────┐
  │ Wait for:          │
  │ - 15s splash time  │
  │ - Verification OK  │
  └────────┬───────────┘
           │
           ▼
  ┌────────────────────┐
  │ Transition to:     │
  │ MainScene.tscn     │
  │                    │
  │ Global variables:  │
  │ - auth_token ✓     │
  │ - player_username ✓│
  │ - is_authenticated ✓
  └────────────────────┘
```

## File Dependencies

```
AuthenticationEntry.tscn
    │
    └─► AuthenticationEntry.gd
            │
            ├─► AuthenticationManager.gd
            │       │
            │       ├─► backend-game-server/src/...
            │       │   (/api/auth/*)
            │       │
            │       └─► user://tinybox_token.json
            │
            └─► AuthenticationScreen.tscn
                    └─► AuthenticationScreen.gd
                            └─► AuthenticationManager.gd
                                    │
                                    └─► SplashVerification.tscn
                                            └─► SplashVerification.gd
                                                    │
                                                    ├─► res://title.png
                                                    │
                                                    ├─► AuthenticationManager.gd
                                                    │
                                                    └─► MainScene.tscn
                                                            (or back to
                                                             AuthenticationScreen)
```

## State Machine

```
┌──────────────────────────────────────────────────────────────┐
│                    Authentication System                      │
│                      State Machine                            │
└──────────────────────────────────────────────────────────────┘

                          STARTUP
                            │
                            ▼
                  ┌────────────────────┐
                  │ CHECKING_TOKEN     │
                  │                    │
                  │ - Load saved token │
                  │ - Check file exist │
                  └────────┬───────────┘
                           │
                   ┌───────┴───────┐
                   │               │
                   ▼               ▼
            ┌────────────┐  ┌──────────────┐
            │ Token      │  │ NO_TOKEN     │
            │ Found      │  │              │
            └────┬───────┘  └────┬─────────┘
                 │               │
                 ▼               ▼
         ┌──────────────┐  ┌────────────────┐
         │ SPLASH_      │  │ REGISTRATION   │
         │ VERIFYING    │  │ OR_LOGIN       │
         │              │  │                │
         │ Verifying... │  │ Show form      │
         └──────┬───────┘  │ Waiting input  │
                │           └────┬───────────┘
                │                │
         ┌──────┴────┐           │
         │           │           │
         ▼           ▼           ▼
    ┌─────────┐ ┌────────┐ ┌─────────────┐
    │ VALID   │ │INVALID │ │ SUBMITTED   │
    │         │ │        │ │             │
    │ Success │ │Expired │ │ Processing  │
    │ State   │ │ Clear  │ │ Request     │
    │         │ │ Token  │ │ Sending     │
    └────┬────┘ └────┬───┘ └────┬────────┘
         │           │          │
         └───────┬───┴──────────┘
                 │
                 ▼
         ┌───────────────┐
         │ LOGIN_        │
         │ REGISTERING   │
         │               │
         │ HTTP Request  │
         │ to Backend    │
         └───────┬───────┘
                 │
                 ├──────────────────┬─────────────────┐
                 │                  │                 │
                 ▼                  ▼                 ▼
         ┌────────────┐      ┌────────────┐  ┌──────────────┐
         │ SUCCESS    │      │ FAILED     │  │ TIMEOUT      │
         │            │      │            │  │              │
         │ Token      │      │ Error msg  │  │ Connection   │
         │ Received   │      │ displayed  │  │ failed       │
         │ Save local │      │ Stay on    │  │ Return login │
         │ → SPLASH   │      │ form       │  │              │
         └────┬───────┘      └────────────┘  └──────────────┘
              │
              ▼
         ┌────────────────┐
         │ AUTHENTICATED  │
         │                │
         │ Ready for game │
         │ Proceed to:    │
         │ MainScene.tscn │
         └────────────────┘
```

## Integration Points

```
Authentication System integrates with:

┌──────────────────────────────────────┐
│ MultiplayerNodeAdapter.gd            │
│                                      │
│ In WebSocket Handshake:              │
│ ┌──────────────────────────────────┐ │
│ │ {                                │ │
│ │   "type": "handshake",           │ │
│ │   "data": {                      │ │
│ │     "version": "0.4.0",          │ │
│ │     "name": Global.player_       │ │
│ │           username,    ◄─────────────── From Auth System
│ │     "token": Global.auth_token   │ │◄── From Auth System
│ │   }                              │ │
│ │ }                                │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘

       ▲
       │ Reads from
       │
┌──────┴───────────────────────────────┐
│ GlobalPlayMenu.gd                    │
│                                      │
│ - Get room list via REST API         │
│   Header: Authorization: Bearer...   │◄── From Global.auth_token
│                                      │
│ - Create/Join rooms via WebSocket    │◄── Pass token in handshake
│                                      │
│ - Access user stats                  │◄── From /api/users/:id/stats
└──────────────────────────────────────┘
```

---

**Last Updated:** January 8, 2026
**Status:** ✅ Architecture Complete - Ready for Integration
