# Exercise Platform — Prototype 0.2

Prototype עובד לליבת מערכת תיעוד ותחקור תרגילים:

`GPS בטלפון → SQLite מקומי → Batch Sync → FastAPI → PostgreSQL/PostGIS → הצגת מסלול על מפה בדפדפן`

## מה נוסף ב-0.2

- מסך Flutter ליצירת תרגיל ניסוי חדש או הצטרפות לפי Exercise ID.
- יצירת Participant ו-Device Session מהמובייל.
- התחלת Exercise מהמובייל לצורך ניסוי.
- מסך Tracking עם מצב GPS, מספר נקודות ומספר נקודות ממתינות לסנכרון.
- שמירה Offline-first ב-SQLite.
- Retry אוטומטי כל 10 שניות כאשר השרת אינו זמין.
- API לרשימת תרגילים ומשתתפים.
- API שמחזיר קואורדינטות GPS אמיתיות מתוך PostGIS.
- ממשק Web ב-`/` עם Leaflet/OpenStreetMap להצגת מסלול של משתתף.

## מבנה

```text
exercise-platform/
├── backend/          FastAPI
├── database/         PostGIS initialization
├── mobile/           Flutter source
├── docker-compose.yml
└── README.md
```

## 1. הפעלת השרת

נדרש Docker Desktop.

מתוך תיקיית הפרויקט:

```bash
docker compose up --build
```

לאחר עלייה:

- Web map: `http://localhost:8000`
- Swagger API: `http://localhost:8000/docs`
- Health: `http://localhost:8000/api/v1/health`

## 2. הכנת Flutter

ראה `mobile/PLATFORM_SETUP.md`.

בקצרה:

```bash
cd mobile
flutter create . --platforms=android,ios
flutter pub get
flutter run
```

## 3. ניסוי הליכה ראשון

1. הפעל את השרת ב-Docker.
2. הפעל את האפליקציה בטלפון/אמולטור.
3. במסך הראשון הזן את כתובת השרת.
4. לחץ **צור, התחל ועבור למעקב**.
5. אשר הרשאות GPS.
6. ודא שמספר `נקודות שנשמרו` עולה.
7. כבה Wi-Fi/נתונים לזמן קצר — `ממתינות לסנכרון` אמור לעלות.
8. החזר אינטרנט — המספר אמור לרדת חזרה ל-0.
9. במחשב פתח `http://localhost:8000`.
10. בחר את התרגיל ואת המשתתף; המסלול יוצג על המפה.

## בדיקת Offline נכונה

המערכת פועלת לפי `SAVE FIRST, SEND SECOND`:

- כל Point נשמר ב-SQLite עם `PENDING`.
- הסנכרון שולח עד 20 Points ב-Batch.
- רק תשובת 2xx מסמנת את ה-Points כ-`SYNCED`.
- `device_session_id + sequence_number` הוא Unique בשרת ולכן Retry אינו יוצר כפילויות.

## מגבלות Prototype 0.2

זהו Prototype הנדסי ולא מוצר Production:

- אין Authentication והרשאות משתמשים עדיין.
- אין QR/Join Code עדיין; הצטרפות מרובת מכשירים נעשית כרגע דרך Exercise ID.
- אין Events/תרחישים בממשק עדיין.
- אין Replay Timeline/Play-Pause עדיין — מוצג מסלול מלא סטטי.
- מעקב Background עמוק/Foreground Service מלא ל-Android ו-background lifecycle מלא ל-iOS עדיין לא הושלמו.
- ה-Web משתמש באריחי OpenStreetMap דרך האינטרנט.
- אין HTTPS בפיתוח המקומי.

## יעד Prototype 0.3

- Join Code/QR.
- Background tracking אמין באנדרואיד וב-iOS.
- אירועי חמ"ל עם זמן ומיקום.
- Live latest-location.
- Timeline בסיסי ו-Replay של כמה משתתפים במקביל.
