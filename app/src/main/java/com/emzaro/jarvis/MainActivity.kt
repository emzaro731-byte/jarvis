package com.emzaro.jarvis
import android.app.Activity
import android.os.Bundle
import android.content.Intent
import android.content.pm.PackageManager
import android.webkit.*
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
class MainActivity : Activity(), TextToSpeech.OnInitListener {
 private lateinit var web: WebView
 private var tts: TextToSpeech? = null
 override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState); tts=TextToSpeech(this,this)
  if(android.os.Build.VERSION.SDK_INT>=33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),773)
  if(android.os.Build.VERSION.SDK_INT>=26){val ch=android.app.NotificationChannel("jarvis_reminders","JARVIS reminders",android.app.NotificationManager.IMPORTANCE_DEFAULT); getSystemService(android.app.NotificationManager::class.java).createNotificationChannel(ch)}
  web=WebView(this); web.settings.javaScriptEnabled=true; web.settings.domStorageEnabled=true
  web.webChromeClient=WebChromeClient(); web.webViewClient=WebViewClient(); web.addJavascriptInterface(Bridge(),"JarvisAndroid")
  setContentView(web); web.loadUrl("file:///android_asset/index.html")
 }
 inner class Bridge {
  @JavascriptInterface fun speak(text:String) { runOnUiThread { tts?.speak(text.take(1500),TextToSpeech.QUEUE_FLUSH,null,"jarvis") } }
  @JavascriptInterface fun listApps():String {
   val pm=packageManager; val i=Intent(Intent.ACTION_MAIN,null).addCategory(Intent.CATEGORY_LAUNCHER); val arr=JSONArray()
   pm.queryIntentActivities(i,PackageManager.MATCH_ALL).sortedBy { it.loadLabel(pm).toString().lowercase() }.forEach {
    val o=JSONObject(); o.put("name",it.loadLabel(pm).toString()); o.put("packageName",it.activityInfo.packageName); arr.put(o)
   }; return arr.toString()
  }
  @JavascriptInterface fun openApp(pkg:String) { runOnUiThread { try { val i=packageManager.getLaunchIntentForPackage(pkg); if(i!=null) startActivity(i) else Toast.makeText(this@MainActivity,"App unavailable",0).show() } catch(_:Exception){} } }
  @JavascriptInterface fun voiceInput() { runOnUiThread { try { val i=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH); i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM); i.putExtra(RecognizerIntent.EXTRA_PROMPT,"Speak to JARVIS"); startActivityForResult(i,771) } catch(_:Exception){ Toast.makeText(this@MainActivity,"Voice input unavailable",0).show() } } }
  @JavascriptInterface fun pickContact() { runOnUiThread { try { startActivityForResult(Intent(Intent.ACTION_PICK,android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI),772) } catch(_:Exception) { Toast.makeText(this@MainActivity,"Contacts picker unavailable",Toast.LENGTH_SHORT).show() } } }
  @JavascriptInterface fun dialNumber(number:String) { runOnUiThread { try { val clean=number.filter { it.isDigit() || it=='+' || it=='*' || it=='#' }; if(clean.isNotBlank()) startActivity(Intent(Intent.ACTION_DIAL,android.net.Uri.parse("tel:"+android.net.Uri.encode(clean)))) } catch(_:Exception) { Toast.makeText(this@MainActivity,"Unable to open phone dialer",Toast.LENGTH_SHORT).show() } } }
  @JavascriptInterface fun openWhatsAppChat(number:String,message:String) { runOnUiThread { try {
   var n=number.filter { it.isDigit() || it=='+' }.replace("+","")
   if(n.startsWith("0")) n="234"+n.drop(1)
   if(n.isBlank()) { Toast.makeText(this@MainActivity,"Contact has no valid phone number",Toast.LENGTH_SHORT).show(); return@runOnUiThread }
   val url="https://wa.me/"+n+"?text="+java.net.URLEncoder.encode(message.take(2000),"UTF-8")
   startActivity(Intent(Intent.ACTION_VIEW,android.net.Uri.parse(url)))
  } catch(_:Exception) { Toast.makeText(this@MainActivity,"WhatsApp is not available. Install or update it.",Toast.LENGTH_LONG).show() } } }
  @JavascriptInterface fun scheduleReminder(title:String,details:String,whenMillis:Long):Boolean {
   if(whenMillis<=System.currentTimeMillis()) return false
   return try { val i=Intent(this@MainActivity,ReminderReceiver::class.java).putExtra("title",title.take(100)).putExtra("details",details.take(500)).putExtra("id",(whenMillis%Int.MAX_VALUE).toInt())
    val pi=android.app.PendingIntent.getBroadcast(this@MainActivity,(whenMillis%Int.MAX_VALUE).toInt(),i,android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
    val am=getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
    am.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP,whenMillis,pi); true
   } catch(_:Exception){ false }
  }
  @JavascriptInterface fun openSettings() { runOnUiThread { startActivity(Intent(android.provider.Settings.ACTION_SETTINGS)) } }
  @JavascriptInterface fun startScreenScan(): Boolean { val svc=ScreenReaderService.instance; if(svc==null){runOnUiThread{startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))};return false}; svc.startPolling(); return true }
  @JavascriptInterface fun stopScreenScan(){ScreenReaderService.instance?.stopPolling()}
  @JavascriptInterface fun screenScanText():String=ScreenReaderService.latestText
  @JavascriptInterface fun batteryPercent():Int { val b=registerReceiver(null,android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)); val l=b?.getIntExtra("level",-1)?:-1; val s=b?.getIntExtra("scale",100)?:100; return if(l>=0&&s>0) l*100/s else -1 }
 }
 override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) { super.onActivityResult(requestCode,resultCode,data)
  if(requestCode==771&&resultCode==RESULT_OK){ val t=data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?:return; web.evaluateJavascript("window.onJarvisVoice("+JSONObject.quote(t)+")",null) }
  if(requestCode==772&&resultCode==RESULT_OK&&data?.data!=null){ try { contentResolver.query(data.data!!,arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER),null,null,null)?.use { c -> if(c.moveToFirst()){ web.evaluateJavascript("window.onJarvisContact("+JSONObject.quote(c.getString(0)?: "Contact")+","+JSONObject.quote(c.getString(1)?: "")+")",null) } } } catch(_:Exception){ Toast.makeText(this,"Could not read selected contact",Toast.LENGTH_SHORT).show() } }
 }
 override fun onInit(status:Int) { if(status==TextToSpeech.SUCCESS) tts?.language=Locale.getDefault() }
 override fun onDestroy(){ tts?.shutdown(); web.destroy(); super.onDestroy() }
}