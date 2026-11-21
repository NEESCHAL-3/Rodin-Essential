package io.github.neeschal.rodinessential;

import android.accessibilityservice.AccessibilityService;
import android.app.KeyguardManager;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityEvent;
import android.widget.TextView;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public final class GameMonitorService extends AccessibilityService {
    static { System.loadLibrary("rodin_essential_host"); }
    private static native String focused();
    private static native String sample(String pkg);
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final BroadcastReceiver screen = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { hide(); }
    };
    private final ExecutorService historyIO = Executors.newSingleThreadExecutor();
    private long startTime;
    private java.io.File session;
    private Integer batteryTenths;
    private final BroadcastReceiver battery = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            batteryTenths = i.hasExtra(BatteryManager.EXTRA_TEMPERATURE)
                ? i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) : null;
        }
    };
    // Only the serial history executor owns these fields.
    private java.io.BufferedWriter historyWriter;
    private java.io.File writerPath;
    private int bufferedSamples;
    private void closeWriter() {
        if (historyWriter != null) {
            try { historyWriter.close(); }
            catch (java.io.IOException e) { android.util.Log.w("RodinGameMonitor","Closing session failed",e); }
        }
        historyWriter=null;
        writerPath=null;
        bufferedSamples=0;
    }
    private void append(java.io.File path, JSONArray row) {
        historyIO.execute(() -> {
            try {
                if (!path.equals(writerPath)) {
                    closeWriter();
                    historyWriter = java.nio.file.Files.newBufferedWriter(path.toPath(),
                        java.nio.charset.StandardCharsets.UTF_8,java.nio.file.StandardOpenOption.CREATE,
                        java.nio.file.StandardOpenOption.APPEND);
                    writerPath=path;
                }
                historyWriter.write(row.toString());
                historyWriter.newLine();
                String kind=row.optString(0);
                if ("end".equals(kind)) closeWriter();
                else if ("start".equals(kind) || ++bufferedSamples>=5) {
                    historyWriter.flush();
                    bufferedSamples=0;
                }
            } catch (java.io.IOException e) {
                android.util.Log.w("RodinGameMonitor","Session write failed",e);
                closeWriter();
            }
        });
    }
    private void beginSession(String pkg) {
        java.io.File dir = new java.io.File(getFilesDir(), "game-history");
        dir.mkdirs();
        long wallTime = System.currentTimeMillis();
        session = new java.io.File(dir, wallTime+"-"+UUID.randomUUID()+".jsonl");
        startTime = SystemClock.elapsedRealtime();
        String label = pkg;
        try { label = getPackageManager().getApplicationLabel(getPackageManager().getApplicationInfo(pkg,0)).toString(); }
        catch (android.content.pm.PackageManager.NameNotFoundException ignored) {}
        append(session,new JSONArray().put("start").put(wallTime).put(pkg).put(label));
        historyIO.execute(() -> {
            java.io.File[] files=dir.listFiles((d,n)->n.endsWith(".jsonl"));
            if(files==null)return;
            Arrays.sort(files);
            for(int i=0;i<files.length-50;i++)files[i].delete();
        });
    }
    private TextView chip;
    private String game;
    private int generation;
    private JSONObject config = new JSONObject();
    private JSONObject position = new JSONObject();
    private void readConfig() {
        try {
            java.io.File file = new java.io.File(getFilesDir(), "game-monitor.json");
            config = new JSONObject(new String(java.nio.file.Files.readAllBytes(file.toPath()), java.nio.charset.StandardCharsets.UTF_8));
        } catch (Exception e) { config = new JSONObject(); }
        JSONObject pos = config.optJSONObject("positions");
        position = pos == null ? new JSONObject() : pos;
    }
    private long previousTotal, previousIdle;
    private WindowManager wm;
    private boolean registered;
    @Override public void onServiceConnected() {
        readConfig();
        wm = getSystemService(WindowManager.class);
        if (!registered) {
            registerReceiver(screen, new IntentFilter(Intent.ACTION_SCREEN_OFF));
            registerReceiver(battery, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            registered = true;
        }
        scheduleFocus();
    }
    private int focusVersion;
    private final Runnable checkFocus = () -> {
        final int version = focusVersion;
        worker.execute(() -> {
            String pkg = focused();
            main.post(() -> {
                if (version != focusVersion || pkg == null || worker.isShutdown()) return;
                updateForeground(pkg);
            });
        });
    };
    private void scheduleFocus() {
        focusVersion++;
        main.removeCallbacks(checkFocus);
        main.postDelayed(checkFocus,120);
    }
    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (wm == null || event.getPackageName() == null) return;
        // Overlay, dialog and popup window events can arrive after an Activity
        // remains resumed. Resolve the app from ActivityManager after settling.
        scheduleFocus();
    }
    private void updateForeground(String pkg) {
        if (!pkg.equals(game)) readConfig();
        JSONObject apps = config.optJSONObject("apps");
        if (apps == null || !apps.optBoolean(pkg,false) || getSystemService(KeyguardManager.class).isKeyguardLocked()) {
            hide(); return;
        }
        if (pkg.equals(game)) return;
        hide();
        game = pkg;
        beginSession(pkg);
        chip = new TextView(this);
        chip.setTextColor(Color.WHITE);
        chip.setTypeface(Typeface.MONOSPACE);
        styleChip();
        chip.setOnTouchListener(this::editChip);
        chip.setText("— FPS");
        wm.addView(chip, params());
        main.post(read);
    }
    private void styleChip() {
        float scale = (float)Math.max(.75,Math.min(1.5, config.optDouble("scale",1)));
        chip.setTextSize(12*scale);
        float density = getResources().getDisplayMetrics().density;
        int px=Math.round(5*density*scale), py=Math.round(2*density*scale);
        chip.setPadding(px,py,px,py);
        android.graphics.drawable.GradientDrawable glass = new android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
            new int[]{0x61334551,0x59212C37});
        glass.setCornerRadius(7*density*scale);
        glass.setStroke(Math.max(1,Math.round(density*.5f)),0x47FFFFFF);
        chip.setBackground(glass);
        chip.setShadowLayer(1.5f * density, 0f, 0.75f * density, 0xDD000000);
    }
    private View resizeSurface;
    private boolean held;
    private final Runnable armResize = () -> {
        if (chip == null) return;
        held = true;
        chip.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        chip.setText("Lift, then pinch anywhere");
        wm.updateViewLayout(chip, params());
    };
    private final Runnable dismissResize = this::closeResize;
    private void closeResize() {
        main.removeCallbacks(dismissResize);
        if (resizeSurface != null) {
            wm.removeView(resizeSurface);
            resizeSurface = null;
        }
        held = false;
    }
    private void openResize() {
        closeResize();
        resizeSurface = new View(this);
        WindowManager.LayoutParams area = new WindowManager.LayoutParams(-1,-1,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT);
        resizeSurface.setOnTouchListener((view,event) -> {
            main.removeCallbacks(dismissResize);
            if(event.getActionMasked()==MotionEvent.ACTION_UP || event.getActionMasked()==MotionEvent.ACTION_CANCEL) {
                editChip(view,event);
                closeResize();
            } else {
                editChip(view,event);
            }
            return true;
        });
        wm.addView(resizeSurface,area);
        chip.setText("Pinch anywhere to resize");
        wm.updateViewLayout(chip,params());
        main.postDelayed(dismissResize,8000);
    }
    private float downX,downY;
    private float lastX, lastY, initialSpan, initialScale;
    private boolean pinch, edited;
    private String orientationKey() {
        return getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE ? "landscape" : "portrait";
    }
    private float span(MotionEvent e) {
        return (float)Math.hypot(e.getRawX(1)-e.getRawX(0),e.getRawY(1)-e.getRawY(0));
    }
    private boolean editChip(View view, MotionEvent e) {
        if (config.optBoolean("locked", false)) return false;
        try {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    lastX=downX=e.getRawX(); lastY=downY=e.getRawY();
                    if(view==chip){held=false;main.postDelayed(armResize,ViewConfiguration.getLongPressTimeout());}
                    pinch=false; edited=false; break;
                case MotionEvent.ACTION_POINTER_DOWN:
                    main.removeCallbacks(armResize);
                    if(e.getPointerCount()==2) {
                        pinch=true; initialSpan=span(e); initialScale=(float)config.optDouble("scale",1);
                    }
                    break;
                case MotionEvent.ACTION_MOVE:
                    if (held) break;
                    if(view==chip && Math.hypot(e.getRawX()-downX,e.getRawY()-downY)>ViewConfiguration.get(this).getScaledTouchSlop()) main.removeCallbacks(armResize);
                    if(pinch && e.getPointerCount()==2 && initialSpan>0) {
                        config.put("scale",Math.max(.75,Math.min(1.5,initialScale*span(e)/initialSpan)));
                        styleChip();
                    } else if(view==chip && !pinch && e.getPointerCount()==1) {
                        WindowManager.LayoutParams p=params();
                        Rect bounds=wm.getCurrentWindowMetrics().getBounds();
                        String key=orientationKey();
                        position.put(key+"x",Math.max(0,Math.min(1,(p.x+e.getRawX()-lastX)/Math.max(1,bounds.width()-chip.getMeasuredWidth()))));
                        position.put(key+"y",Math.max(0,Math.min(1,(p.y+e.getRawY()-lastY)/Math.max(1,bounds.height()-chip.getMeasuredHeight()))));
                        lastX=e.getRawX(); lastY=e.getRawY();
                    } else break;
                    edited=true;
                    wm.updateViewLayout(chip,params());
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    main.removeCallbacks(armResize);
                    if(view==chip && held && e.getActionMasked()==MotionEvent.ACTION_UP){ openResize(); break; }
                    held=false;
                    if(edited) {
                        config.put("positions",position);
                        java.nio.file.Path dest=new java.io.File(getFilesDir(),"game-monitor.json").toPath();
                        java.nio.file.Path temp=dest.resolveSibling("game-monitor.live.tmp");
                        java.nio.file.Files.write(temp,config.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                        java.nio.file.Files.move(temp,dest,java.nio.file.StandardCopyOption.ATOMIC_MOVE,java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                    edited=false; pinch=false; break;
                default: break;
            }
        } catch(Exception ex) { android.util.Log.w("RodinGameMonitor","Overlay placement failed",ex); }
        return true;
    }
    private WindowManager.LayoutParams params() {
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(-2,-2,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                | (config.optBoolean("locked",false) ? WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE : 0),
            PixelFormat.TRANSLUCENT);
        p.gravity = Gravity.TOP | Gravity.LEFT;
        Rect bounds = wm.getCurrentWindowMetrics().getBounds();
        chip.measure(0,0);
        String key = getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE ? "landscape" : "portrait";
        p.x = Math.round((float)position.optDouble(key+"x",0.03)*Math.max(0,bounds.width()-chip.getMeasuredWidth()));
        p.y = Math.round((float)position.optDouble(key+"y",0.05)*Math.max(0,bounds.height()-chip.getMeasuredHeight()));
        return p;
    }
    private final Runnable read = new Runnable() {
        public void run() {
            final int token = generation;
            final String pkg = game;
            if (pkg == null) return;
            worker.execute(() -> {
                String raw = sample(pkg);
                main.post(() -> {
                    if (token != generation || chip == null) return;
                    CharSequence stats = format(raw);
                    if(!held && (resizeSurface==null || pinch)) chip.setText(stats);
                    WindowManager.LayoutParams next=params();
                    WindowManager.LayoutParams current=(WindowManager.LayoutParams)chip.getLayoutParams();
                    if(current.x!=next.x || current.y!=next.y) wm.updateViewLayout(chip,next);
                    main.postDelayed(this, 1000);
                });
            });
        }
    };
    private CharSequence format(String raw) {
        JSONObject data;
        try { data = new JSONObject(raw == null ? "{}" : raw); }
        catch (JSONException ex) { data = new JSONObject(); }
        JSONArray times = data.optJSONArray("present");
        TreeSet<Long> recent = new TreeSet<>();
        long now = System.nanoTime();
        if (times != null) for (int i=0; i<times.length(); i++) {
            long t=times.optLong(i);
            if (t <= now && now-t <= 1_000_000_000L) recent.add(t);
        }
        String fps = (times == null || times.length()==0 ? "—" : String.valueOf(recent.size()))+" FPS";

        JSONArray cpu = data.optJSONArray("cpu");
        Long cpuPercent=null;
        if (cpu != null && cpu.length()==2) {
            long total=cpu.optLong(0), idle=cpu.optLong(1);
            long dt=total-previousTotal, di=idle-previousIdle;
            if (previousTotal>0 && dt>0 && di>=0 && di<=dt) cpuPercent=Math.round(100.0*(dt-di)/dt);
            previousTotal=total; previousIdle=idle;
        } else { previousTotal=0; }
        int gpu=data.optInt("gpu",-1);
        Integer gpuPercent=gpu>=0 && gpu<=100?gpu:null;
        append(session,new JSONArray().put("sample").put(SystemClock.elapsedRealtime()-startTime)
            .put(times==null || times.length()==0 ? JSONObject.NULL : recent.size())
            .put(batteryTenths==null ? JSONObject.NULL : batteryTenths)
            .put(cpuPercent==null ? JSONObject.NULL : cpuPercent).put(gpuPercent==null ? JSONObject.NULL : gpuPercent));
        if (!config.optBoolean("details",false)) return fps;
        String load=cpuPercent==null?"—":cpuPercent+"%";
        android.text.SpannableString text = new android.text.SpannableString(fps+"\nCPU "+load+"   GPU "+(gpuPercent==null?"—":gpuPercent+"%"));
        text.setSpan(new android.text.style.StyleSpan(Typeface.BOLD),0,fps.length(),0);
        text.setSpan(new android.text.style.RelativeSizeSpan(.82f),fps.length()+1,text.length(),0);
        text.setSpan(new android.text.style.ForegroundColorSpan(0xffdae8e6),fps.length()+1,text.length(),0);
        return text;
    }
    private void hide() {
        main.removeCallbacks(armResize);
        closeResize();
        if (session!=null) {
            append(session,new JSONArray().put("end").put(SystemClock.elapsedRealtime()-startTime));
            session=null;
        }
        generation++;
        game=null;
        previousTotal=0;
        main.removeCallbacks(read);
        if (chip!=null) { wm.removeView(chip); chip=null; }
    }
    @Override public void onConfigurationChanged(Configuration config) {
        super.onConfigurationChanged(config);
        if (chip!=null) wm.updateViewLayout(chip,params());
    }
    @Override public void onInterrupt() { hide(); }
    @Override public void onDestroy() {
        main.removeCallbacks(checkFocus);
        focusVersion++;
        hide();
        if (registered) { unregisterReceiver(screen); unregisterReceiver(battery); }
        historyIO.shutdown();
        worker.shutdownNow();
        super.onDestroy();
    }
}
