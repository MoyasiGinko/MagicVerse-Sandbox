# Worlds API Documentation

## Overview

The Worlds API provides endpoints for managing game maps/worlds in the Tinybox server.

## Base URL

```
http://localhost:30820/api/worlds
```

## Endpoints

### GET /api/worlds

Get all worlds, optionally filtered by featured status.

**Query Parameters:**

- `featured` (optional): `true` or `false` to filter by featured status

**Response:**

```json
{
  "success": true,
  "worlds": [
    {
      "id": 1,
      "name": "Frozen Field",
      "featured": true,
      "date": "2026-01-08",
      "downloads": 150,
      "version": "1.0.0",
      "author": "CaelanDouglas",
      "image": "base64_or_url_here",
      "tbw": "map_data_here",
      "reports": 0,
      "updated_at": "2026-01-08T12:30:00.000Z"
    }
  ]
}
```

### GET /api/worlds/search

Search worlds by name or author.

**Query Parameters:**

- `q` (required): Search term

**Example:**

```
GET /api/worlds/search?q=frozen
```

**Response:**

```json
{
  "success": true,
  "worlds": [
    /* matching worlds */
  ]
}
```

### GET /api/worlds/:id

Get a specific world by ID.

**Response:**

```json
{
  "success": true,
  "world": {
    "id": 1,
    "name": "Frozen Field",
    "featured": true,
    "date": "2026-01-08",
    "downloads": 150,
    "version": "1.0.0",
    "author": "CaelanDouglas",
    "image": "base64_or_url_here",
    "tbw": "map_data_here",
    "reports": 0,
    "updated_at": "2026-01-08T12:30:00.000Z"
  }
}
```

### POST /api/worlds

Create a new world. **Requires authentication.**

**Headers:**

```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Body:**

```json
{
  "name": "My Custom Map",
  "featured": false,
  "version": "1.0.0",
  "author": "username",
  "image": "base64_encoded_image_or_url",
  "tbw": "map_data_in_tbw_format"
}
```

**Response:**

```json
{
  "success": true,
  "world": {
    "id": 5,
    "name": "My Custom Map",
    "featured": false,
    "date": "2026-01-08",
    "downloads": 0,
    "version": "1.0.0",
    "author": "username",
    "image": "...",
    "tbw": "...",
    "reports": 0,
    "updated_at": "2026-01-08T12:30:00.000Z"
  }
}
```

### PUT /api/worlds/:id

Update an existing world. **Requires authentication.**

**Headers:**

```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Body:** (all fields optional)

```json
{
  "name": "Updated Name",
  "featured": true,
  "version": "1.1.0",
  "author": "username",
  "image": "new_image",
  "tbw": "updated_map_data"
}
```

**Response:**

```json
{
  "success": true,
  "world": {
    /* updated world */
  }
}
```

### DELETE /api/worlds/:id

Delete a world. **Requires authentication.**

**Headers:**

```
Authorization: Bearer <jwt_token>
```

**Response:**

```json
{
  "success": true,
  "message": "World deleted successfully"
}
```

### POST /api/worlds/:id/download

Increment the download count for a world.

**Response:**

```json
{
  "success": true,
  "world": {
    /* world with incremented downloads */
  }
}
```

### POST /api/worlds/:id/report

Report a world for inappropriate content.

**Response:**

```json
{
  "success": true,
  "message": "Report submitted successfully"
}
```

## Database Schema

```sql
CREATE TABLE worlds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name VARCHAR(255) NOT NULL,
  featured BOOLEAN NOT NULL DEFAULT 0,
  date DATE NOT NULL,
  downloads INTEGER NOT NULL DEFAULT 0 CHECK (downloads >= 0),
  version VARCHAR(64) NOT NULL,
  author VARCHAR(255) NOT NULL,
  image TEXT NOT NULL,
  tbw TEXT NOT NULL,
  reports INTEGER NOT NULL DEFAULT 0 CHECK (reports >= 0),
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_worlds_featured ON worlds(featured);
CREATE INDEX idx_worlds_author ON worlds(author);
CREATE INDEX idx_worlds_downloads ON worlds(downloads);
```

## Usage in Godot

### Fetch All Worlds

```gdscript
var http := HTTPRequest.new()
add_child(http)
http.request_completed.connect(_on_worlds_response)

var url := "http://localhost:30820/api/worlds"
http.request(url, ["Content-Type: application/json"])
```

### Create World

```gdscript
var http := HTTPRequest.new()
add_child(http)
http.request_completed.connect(_on_create_response)

var url := "http://localhost:30820/api/worlds"
var headers := [
    "Authorization: Bearer " + Global.auth_token,
    "Content-Type: application/json"
]
var body := JSON.stringify({
    "name": "My Map",
    "version": "1.0.0",
    "author": Global.display_name,
    "image": "base64_image",
    "tbw": "map_data"
})

http.request(url, headers, HTTPClient.METHOD_POST, body)
```

## Integration with Room Creation

The `RoomCreationDialog` now fetches maps from this API:

1. When dialog opens, fetches `GET /api/worlds`
2. Populates map dropdown with world names
3. Selected map name is included in room creation request
4. Falls back to hardcoded maps if API fails

## Error Responses

All endpoints may return error responses:

**400 Bad Request**

```json
{
  "error": "Missing required fields: name, version, author, image, tbw"
}
```

**401 Unauthorized**

```json
{
  "error": "Authentication required"
}
```

**404 Not Found**

```json
{
  "error": "World not found"
}
```

**500 Internal Server Error**

```json
{
  "error": "Internal server error"
}
```
