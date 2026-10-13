package com.emzaro.jarvis
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Notification
import android.os.Build
class ReminderReceiver: BroadcastReceiver(){
 override fun onReceive(context:Context,intent:Intent){
  val title=intent.getStringExtra("title")?: "JARVIS reminder"
  val details=intent.getStringExtra("details")?: "Open JARVIS to continue."
  val id=intent.getIntExtra("id",System.currentTimeMillis().toInt())
  val open=Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
  val pi=PendingIntent.getActivity(context,id,open,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  val b=if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,"jarvis_reminders") else @Suppress("DEPRECATION") Notification.Builder(context)
  val n=b.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(details).setStyle(Notification.BigTextStyle().bigText(details)).setContentIntent(pi).setAutoCancel(true).build()
  val nm=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  if(Build.VERSION.SDK_INT<33 || context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==android.content.pm.PackageManager.PERMISSION_GRANTED) nm.notify(id,n)
 }
}