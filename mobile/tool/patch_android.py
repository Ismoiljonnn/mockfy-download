"""After `flutter create`, makes the Android project Mockfy's: the app name, internet, the browser for
sign-in and links (Android 11+ needs <queries>), and mockfy://auth links opening the app."""
import pathlib
import re

m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text(encoding='utf-8')

s = re.sub(r'android:label="[^"]*"', 'android:label="Mockfy"', s, count=1)
if 'REQUEST_INSTALL_PACKAGES' not in s:      # the app installs its own updates (Android still asks the user)
    s = s.replace('<application', '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n    <application', 1)
if 'RECORD_AUDIO' not in s:                    # Speaking answers
    s = s.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application', 1)
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

deep = '''            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="mockfy" android:host="auth"/>
            </intent-filter>
        </activity>'''
if 'android:scheme="mockfy"' not in s:
    s = s.replace('        </activity>', deep, 1)

queries = '''    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>
</manifest>'''
if '<data android:scheme="https"/>' not in s:
    s = s.replace('</manifest>', queries, 1) if '<queries>' not in s else s.replace(
        '<queries>', '<queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n'
        '            <data android:scheme="https"/>\n        </intent>', 1)

m.write_text(s, encoding='utf-8')
print(s)

# One permanent signing key (from the ANDROID_KEYSTORE_B64 / ANDROID_KEY_PASSWORD secrets, written to
# android/app/upload.jks by the workflow): Android installs an update only when it is signed like the
# version already on the phone. Without the key file the build falls back to a debug key.
g = pathlib.Path('android/app/build.gradle.kts')
if g.exists():
    k = g.read_text(encoding='utf-8')
    if 'upload.jks' not in k:
        k = k.replace('    buildTypes {', '''    signingConfigs {
        create("release") {
            val ks = file("upload.jks")
            if (ks.exists()) {
                storeFile = ks
                storePassword = System.getenv("ANDROID_KEY_PASSWORD")
                keyAlias = "mockfy"
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {''', 1)
        k = k.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = if (file("upload.jks").exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', 1)
        g.write_text(k, encoding='utf-8')

# Notifications: permission (Android 13+), the receivers that bring scheduled reminders back after a
# reboot, and core library desugaring (flutter_local_notifications needs it).
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text(encoding='utf-8')
for perm in ('POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'VIBRATE'):
    if perm not in s:
        s = s.replace('<application', f'<uses-permission android:name="android.permission.{perm}"/>\n    <application', 1)
if 'ScheduledNotificationReceiver' not in s:
    s = s.replace('</application>', """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>""", 1)
m.write_text(s, encoding='utf-8')

g = pathlib.Path('android/app/build.gradle.kts')
if g.exists():
    k = g.read_text(encoding='utf-8')
    if 'isCoreLibraryDesugaringEnabled' not in k:
        k = re.sub(r'compileOptions \{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', k, count=1)
        k += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        g.write_text(k, encoding='utf-8')
