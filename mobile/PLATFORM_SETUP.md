# Mobile platform setup — Prototype 0.2

תיקיית `mobile/` מכילה את קוד ה-Flutter של האפליקציה. מאחר שסביבת הבנייה שבה נוצר ה-Prototype אינה כוללת Flutter SDK, קבצי ה-platform (`android/`, `ios/`) אינם נוצרים אוטומטית כאן.

## יצירת מעטפת Flutter

מתוך תיקיית `mobile`:

```bash
flutter create . --platforms=android,ios
flutter pub get
```

הפקודה לא אמורה למחוק את `lib/` ו-`pubspec.yaml`, אך מומלץ לעבוד מעותק/Git.

## Android

בקובץ `android/app/src/main/AndroidManifest.xml`, לפני תגית `<application>`, הוסף:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

לבדיקה מקומית מול שרת HTTP במחשב, בתוך `<application>` הוסף זמנית:

```xml
android:usesCleartextTraffic="true"
```

> Prototype 0.2 שומר ומסנכרן GPS כאשר האפליקציה פעילה. שירות Foreground מלא להמשך מעקב אמין גם כשהאפליקציה נהרגת/ברקע עמוק הוא יעד לגרסה 0.3 ודורש implementation ייעודי.

### כתובת שרת

- Android Emulator: `http://10.0.2.2:8000`
- טלפון אמיתי: `http://<IP-של-המחשב-ברשת>:8000`

ודא שחומת האש מאפשרת TCP 8000.

## iOS

ב-`ios/Runner/Info.plist` הוסף:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>האפליקציה מתעדת מיקום לצורך שחזור ותחקור התרגיל.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>האפליקציה זקוקה למיקום גם ברקע בזמן תרגיל פעיל.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

לשרת HTTP מקומי בפיתוח ייתכן שתידרש גם הגדרת ATS מתאימה. בייצור יש להשתמש ב-HTTPS.

## הרצה

```bash
flutter run
```

במסך הראשון:

1. הזן כתובת שרת.
2. הזן שם ואות קריאה.
3. בחר **צור, התחל ועבור למעקב**.
4. אשר הרשאות מיקום.
5. צא להליכה.
6. בדפדפן במחשב פתח `http://localhost:8000` ובחר את התרגיל והמשתתף.
