# 📱 LinkUp — Video Conferencing App

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Agora](https://img.shields.io/badge/Agora-RTC%20Engine-099DFD?style=for-the-badge&logo=agora&logoColor=white)

**A lightweight, cross-platform video conferencing application built with Flutter.**  
Connect, collaborate, and communicate — instantly.

</div>

---

## ✨ Features

### 🎥 Video Conferencing
- Real-time HD video and audio via **Agora RTC Engine**
- Dynamic video grid — 1 (fullscreen) / 2 (split) / 3 (1+2) / 4+ (scrollable grid)
- Video quality selector — 360p, 480p, 720p, 1080p
- Camera flip (front/back), mute/unmute, camera on/off

### 🏷️ Meeting Types
| Type | Features |
|------|----------|
| 🎓 **Class** | Attendance tracking · Students join muted · Moderated chat · Timeline |
| 💼 **Team** | Screen share priority · Open mic · Collaboration mode |
| 😊 **Casual** | All features unlocked · No restrictions |

### 🔐 Waiting Room (Private Meetings)
- Host can mark meetings as **Public** or **Private**
- Private → participants enter a waiting room
- Host gets real-time admit/reject alerts
- Auto-timeout after 2 minutes if host doesn't respond

### 🖥️ Screen Sharing
- Zoom/Meet style — large presenter view + horizontal participant strip
- Real-time signal to all participants when sharing starts/stops

### 👨‍💼 Host Controls
- Mute / Request unmute per participant
- Disable / Enable chat per participant
- Mute All / Unmute All (broadcast)
- Enable chat for all participants at once

### 💬 Chat
- **In-meeting chat** — real-time via Supabase Realtime
- **Direct messaging** — private conversations between users
- Optimistic UI — messages appear instantly
- Chat auto-deleted when meeting ends (count saved)

### 📅 Scheduling
- Schedule meetings with date, time, and meeting type
- Countdown display — "In 2h 30m", "Tomorrow", "Starting Soon"
- Grace period — meeting stays visible for 15 minutes after scheduled time
- Past meetings auto-move to history

### 📊 Analytics & Timeline
- Meeting event log — join, leave, screen share, start, end
- Attendance tracking with on-time/late badges (Class mode)
- Late join catch-up — shows duration, speaker, screen share status, recent messages
- User profile analytics — meetings count, time spent, screens shared, activity %

### 🔔 Notifications
- Real-time push notifications for meeting events
- Unread badge on notification bell
- Swipe to dismiss individual notifications

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter (Dart) |
| **Backend** | Supabase (PostgreSQL + Realtime + Auth + Storage) |
| **Video/Audio** | Agora RTC Engine SDK |
| **Token Server** | Node.js on Render.com |
| **State Management** | setState + Supabase Realtime subscriptions |

---

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point
├── screens/
│   ├── splash_screen.dart       # Animated splash + auth check
│   ├── home_screen.dart         # Main dashboard
│   ├── meeting_screen.dart      # Video call screen
│   ├── schedule_screen.dart     # Meeting scheduler
│   ├── chat_screen.dart         # Direct messages list
│   ├── chat_detail_screen.dart  # DM conversation
│   ├── profile_screen.dart      # User profile + analytics
│   ├── meeting_timeline_screen.dart  # Event log + attendance
│   └── waiting_room_screen.dart # Private meeting queue
├── widgets/
│   ├── meeting_card.dart        # Upcoming meeting card
│   └── quick_action_card.dart   # Home screen action buttons
└── meeting_theme.dart           # Per-type color theming
```

---

## 🗄️ Database Schema

<details>
<summary>Click to expand — 9 tables</summary>

### `profiles`
| Column | Type | Description |
|--------|------|-------------|
| id | UUID (PK) | Links to auth.users |
| username | TEXT | Display name |
| email | TEXT | User email |
| avatar_url | TEXT | Profile picture URL |

### `meetings`
| Column | Type | Description |
|--------|------|-------------|
| id | UUID (PK) | Unique meeting ID |
| meeting_code | TEXT (UNIQUE) | Shareable code e.g. `abc-1234-xyz` |
| host_id | UUID (FK) | Meeting creator |
| meeting_type | TEXT | class / team / casual |
| is_active | BOOLEAN | Live status |
| is_private | BOOLEAN | Public or waiting room |
| scheduled_at | TIMESTAMPTZ | Planned start time (nullable) |
| duration_minutes | INTEGER | Saved on meeting end |
| message_count | INTEGER | Chat messages saved before delete |
| show_in_recent | BOOLEAN | Controls recent list visibility |

### `meeting_participants` · `meeting_events` · `meeting_signals`
> Track joins/leaves, timeline events, and host control signals (mute, chat disable, screen share).

### `messages` · `chats` · `chat_messages`
> In-meeting chat (deleted after meeting) and persistent direct messages.

### `notifications` · `waiting_room`
> User alerts and private meeting queue management.

</details>

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.0+
- Dart 3.0+
- Android Studio / VS Code
- Supabase account
- Agora account

### 1. Clone the repository
```bash
git clone https://github.com/Piyush8090/linkup.git
cd linkup
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Configure environment variables

Create a `.env` file in the project root:
```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
AGORA_APP_ID=your_agora_app_id
TOKEN_SERVER_URL=your_token_server_url
```

> ⚠️ Never commit `.env` to version control. See `.env.example` for required keys.

### 4. Set up Supabase

Run the following SQL in your Supabase SQL Editor:

```sql
-- Required columns (run if not already present)
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS message_count INT DEFAULT 0;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS show_in_recent BOOLEAN DEFAULT true;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT false;

-- Waiting room table
CREATE TABLE IF NOT EXISTS waiting_room (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  meeting_code TEXT NOT NULL,
  user_id UUID REFERENCES profiles(id),
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  agora_uid INTEGER NOT NULL,
  status TEXT DEFAULT 'waiting',
  requested_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 5. Run the app
```bash
flutter run
```

---

## 🔑 Environment Variables

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Your Supabase project URL |
| `AGORA_APP_ID` | Agora project App ID |

---

## 📱 Screenshots

<img width="283" height="598" alt="image" src="https://github.com/user-attachments/assets/efb5d10d-2298-43cf-bd54-8c3da31bbf13" />
<img width="280" height="589" alt="image" src="https://github.com/user-attachments/assets/10e47867-8e71-4124-a285-b1bc6d5c1921" />
<img width="281" height="597" alt="image" src="https://github.com/user-attachments/assets/505065b6-59f9-4071-ac1d-161340b685e0" />
<img width="283" height="413" alt="image" src="https://github.com/user-attachments/assets/cedebc52-12bc-4686-a3f6-d77bc5994283" />
<img width="278" height="597" alt="image" src="https://github.com/user-attachments/assets/5b69de5b-908b-4237-a4c7-32012a08f421" />
<img width="283" height="591" alt="image" src="https://github.com/user-attachments/assets/80bcf032-f90d-4330-af2d-03f6bd199f66" />
<img width="280" height="594" alt="image" src="https://github.com/user-attachments/assets/b077910e-a5b3-466d-8a43-7049a98ab817" />
<img width="275" height="588" alt="image" src="https://github.com/user-attachments/assets/30cc4210-e130-4bd0-802f-92844e5574db" />
<img width="277" height="602" alt="image" src="https://github.com/user-attachments/assets/9352fb19-e6cf-4563-bc23-afef033fb823" />
<img width="284" height="592" alt="image" src="https://github.com/user-attachments/assets/beda5d1b-ffa0-466a-af2e-2d28480c3095" />

 


---

## 🔒 Security

- All API keys stored in `.env` — never committed to Git
- Supabase Row Level Security (RLS) enabled
- Agora tokens generated server-side via token server
- Meeting codes are randomly generated — not guessable
- Private meetings require explicit host approval

---

## 📋 Known Limitations

- Screen sharing requires Android (iOS needs additional entitlements)
- Recording not supported in current version
- Optimized for small-to-medium meetings (up to ~20 participants)
- Requires stable internet connection (minimum 2 Mbps for HD video)

---

## 🔮 Future Scope

- [ ] Meeting recording to cloud storage
- [ ] Breakout rooms
- [ ] AI-powered meeting transcription
- [ ] Full iOS screen sharing support
- [ ] Web app (Flutter Web)
- [ ] Dark mode toggle
- [ ] Whiteboard collaboration

---

## 👨‍💻 Author

**Arpit Upadhyay**  
**Satyendra Kumar**
BCA VIth Semester — The Study Hall College, Lucknow  
University of Lucknow

---

## 📄 License

This project is developed as an academic project for BCA Final Year.  
© 2025–2026 Arpit Upadhyay & Satyendra Kumar. All rights reserved.

---

<div align="center">
  Built with ❤️ using Flutter + Supabase + Agora
</div>
