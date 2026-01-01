# Backend Integration Specification: Video Duration Limits

## Overview
The frontend application has been updated to support dynamic video duration limits control. This allows the backend to specify exactly how long a video can be processed for each specific user, overriding the default app-side limits.

## User Object Update
Please update the User response DTO (returned in `/login`, `/register`, `/me`, or user profile endpoints) to include the new duration limit field.

### Field Specification
*   **Field Name**: `maxVideoDuration` (preferred) OR `max_video_duration`
*   **Data Type**: `Number` (Float/Double/Integer)
*   **Unit**: Seconds
*   **Nullable**: `true`

### Client-Side Logic
The mobile/web client processes this field as follows:

1.  **If `maxVideoDuration` IS provided (not null)**:
    *   The app will force the video preparation step to trim the video to this exact duration.
    *   *Example*: If `maxVideoDuration: 600`, the user can only process up to 10 minutes, regardless of their subscription status.

2.  **If `maxVideoDuration` IS NULL (or missing)**:
    *   **Premium Users** (identified by `hasUnlimitedAccess: true` OR `remainingPaidMinutes > 0`):
        *   Default limit: **36000 seconds (10 hours)** (effectively unlimited).
    *   **Free Users**:
        *   Default limit: **120 seconds**.

### JSON Example

```json
{
  "id": "12345",
  "username": "testuser",
  "email": "test@example.com",
  "hasUnlimitedAccess": false,
  
  // Existing fields...
  "remainingPaidMinutes": 0,
  "freeMinutesLimit": 15.0,
  
  // NEW FIELD
  "maxVideoDuration": 300.0 
  // Result: This specific user is limited to 5 minutes (300 seconds) 
  // instead of the default 120s for free users.
}
```

## Implementation Notes
*   **Parsers**: The app's JSON parser looks for both `maxVideoDuration` and `max_video_duration`, so snake_case is also acceptable.
*   **Use Case**: This is useful for creating intermediate tiers (e.g., "Silver Plan" with 30 min limit) or for temporarily boosting a free user's capacity without giving them full unlimited access.
