package com.emzaro.jarvis
import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.os.Handler
import android.os.Looper
class ScreenReaderService : AccessibilityService() {
 companion object { @Volatile var instance:ScreenReaderService?=null; @Volatile var latestText:String="" }
 @Volatile private var scanning=false
 private val handler=Handler(Looper.getMainLooper())
 private val poll=object:Runnable{override fun run(){if(!scanning)return;try{val lines=mutableListOf<String>();collect(rootInActiveWindow,lines,0);latestText=lines.distinct().joinToString("\n").take(12000)}catch(_:Exception){latestText=""};if(scanning)handler.postDelayed(this,700L)}}
 override fun onServiceConnected(){super.onServiceConnected();instance=this;startPolling()}
 override fun onAccessibilityEvent(event:AccessibilityEvent?){}
 override fun onInterrupt(){stopPolling()}
 override fun onDestroy(){stopPolling();if(instance===this)instance=null;super.onDestroy()}
 fun startPolling(){scanning=true;handler.removeCallbacks(poll);handler.post(poll)}
 fun stopPolling(){scanning=false;handler.removeCallbacks(poll);latestText=""}
 fun isPolling():Boolean=scanning
 private fun collect(n:AccessibilityNodeInfo?,out:MutableList<String>,depth:Int){if(n==null||depth>35||out.size>600)return;val t=n.text?.toString()?.trim();if(!t.isNullOrEmpty())out.add(t);val d=n.contentDescription?.toString()?.trim();if(!d.isNullOrEmpty()&&d!=t)out.add(d);for(i in 0 until n.childCount)collect(n.getChild(i),out,depth+1)}
}