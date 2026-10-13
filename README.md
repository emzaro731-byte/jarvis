# JARVIS AI Launcher
Futuristic Android launcher with neon-blue UI, app drawer, voice input, speech output, Android settings shortcut and Groq AI chat.
## Build APK
Open GitHub Actions → Build JARVIS Android APK → Run workflow (or push changes). Download the jarvis-debug-apk artifact, extract it, and install the APK. Press Home and select JARVIS to use it as your launcher.
## AI
Open AI Settings in the app and enter your own Groq API key. It is saved in app-local storage. Never commit API keys to GitHub. Internet is required for AI chat.
This is an initial launcher build. Android restricts certain system controls; protected settings and always-on hotword listening are not bypassed.