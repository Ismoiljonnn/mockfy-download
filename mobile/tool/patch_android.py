"""After `flutter create`, makes the Android project Mockfy's: the app name, internet, the browser for
sign-in and links (Android 11+ needs <queries>), and mockfy://auth links opening the app."""
import pathlib
import re

m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text(encoding='utf-8')

s = re.sub(r'android:label="[^"]*"', 'android:label="Mockfy"', s, count=1)
if 'REQUEST_INSTALL_PACKAGES' not in s:      # the app installs its own updates (Android still asks the user)
    s = s.replace('<application', '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n    <application', 1)
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
