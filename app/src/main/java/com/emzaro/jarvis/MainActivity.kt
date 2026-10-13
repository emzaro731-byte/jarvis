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
  @JavascriptInterface fun openSettings() { runOnUiThread { startActivity(Intent(android.provider.Settings.ACTION_SETTINGS)) } }
  @JavascriptInterface fun startScreenScan(): Boolean { val svc=ScreenReaderService.instance; if(svc==null){runOnUiThread{startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))};return false}; svc.startPolling(); return true }
  @JavascriptInterface fun stopScreenScan(){ScreenReaderService.instance?.stopPolling()}
  @JavascriptInterface fun screenScanText():String=ScreenReaderService.latestText
  @JavascriptInterface fun batteryPercent():Int { val b=registerReceiver(null,android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)); val l=b?.getIntExtra("level",-1)?:-1; val s=b?.getIntExtra("scale",100)?:100; return if(l>=0&&s>0) l*100/s else -1 }
 }
 override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) { super.onActivityResult(requestCode,resultCode,data); if(requestCode==771&&resultCode==RESULT_OK){ val t=data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?:return; web.evaluateJavascript("window.onJarvisVoice("+JSONObject.quote(t)+")",null) } }
 override fun onInit(status:Int) { if(status==TextToSpeech.SUCCESS) tts?.language=Locale.getDefault() }
 override fun onDestroy(){ tts?.shutdown(); web.destroy(); super.onDestroy() }
}