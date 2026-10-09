package io.github.neeschal.rodinessential;

import android.os.Handler;
import android.os.Looper;
import android.graphics.drawable.Icon;
import android.animation.ValueAnimator;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.animation.DecelerateInterpolator;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** SystemUI owns the tile. The daemon owns charging. Never flip a fake state. */
public final class BypassTileService extends TileService {
    static { System.loadLibrary("rodin_essential_host"); }
    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean listening;
    private int lastState = -1;
    private Icon[] motionIcons;
    private ValueAnimator iconMotion;
    private int iconFrame;
    private static final int LAST_ICON_FRAME = 16;
    private final Runnable update = new Runnable() {
        @Override public void run() {
            if (!listening) return;
            publish();
            main.postDelayed(this, (lastState & 16) != 0 ? 80 : 500);
        }
    };
    private static native void nativeStart();
    private static native int nativeSnapshot();
    private static native boolean nativeToggle();
    @Override public void onStartListening() {
        super.onStartListening(); nativeStart(); listening = true; lastState = -1;
        main.removeCallbacks(update); main.post(update);
    }
    @Override public void onStopListening() {
        listening = false; main.removeCallbacks(update); stopIconMotion(); super.onStopListening();
    }
    @Override public void onDestroy() {
        listening = false; main.removeCallbacks(update); stopIconMotion(); super.onDestroy();
    }
    @Override public void onClick() {
        super.onClick();
        if (isLocked()) { unlockAndRun(this::toggle); return; }
        toggle();
    }
    private void toggle() {
        if (!nativeToggle()) return;
        publish();
        main.removeCallbacks(update);
        if (listening) main.postDelayed(update, 80);
    }
    private void publish() {
        Tile tile = getQsTile();
        if (tile == null) return;
        int state = nativeSnapshot();
        if (state == lastState) return;
        boolean available = (state & 35) == 35;
        boolean enabled = (state & 4) != 0;
        int phase = (state >> 7) & 15;
        String status = (state & 1) == 0 ? "Daemon unavailable"
            : (state & 32) == 0 ? "Controls disabled"
            : (state & 2) == 0 ? "Not supported"
            : (state & 16) != 0 ? "Updating…"
            : (state & 64) != 0 ? "Check charging status"
            : enabled && (state & 8) != 0 ? "Active · direct power"
            : enabled && phase == 7 ? "Charging detected"
            : enabled && phase == 6 ? "Battery assist"
            : enabled && phase == 1 ? "Charging to threshold"
            : enabled && phase == 2 ? "Enabled · connect charger"
            : enabled ? "Power settling" : "Off";
        // Animate only a confirmed ON/OFF change. Unchanged snapshots never
        // resend the drawable; SystemUI controls animation and reduced motion.
        boolean changed = lastState >= 0 && available && (lastState & 35) == 35
            && ((lastState ^ state) & 4) != 0;
        // Remote animated vectors are frozen by some OEM Control Centers.
        // Initial/resting states use vectors; a confirmed toggle gets cached
        // cached monochrome frames. Status updates never reset the animation.
        if (!changed && (lastState < 0 || ((lastState ^ state) & 4) != 0)) {
            stopIconMotion();
            iconFrame = enabled ? LAST_ICON_FRAME : 0;
            String drawable = enabled ? "ic_bypass_on" : "ic_bypass";
            int icon = getResources().getIdentifier(drawable, "drawable", getPackageName());
            if (icon != 0) tile.setIcon(Icon.createWithResource(this, icon));
        }
        tile.setLabel("Bypass charging");
        tile.setSubtitle(status);
        tile.setState(!available ? Tile.STATE_UNAVAILABLE
            : enabled ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setContentDescription("Bypass charging, " + status);
        tile.updateTile();
        lastState = state;
        if (changed) animateIcon(enabled);
    }

    private void stopIconMotion() {
        if (iconMotion != null) { iconMotion.cancel(); iconMotion = null; }
    }

    private void animateIcon(boolean enabled) {
        stopIconMotion();
        if (!listening) return;
        if (motionIcons == null) {
            motionIcons = new Icon[LAST_ICON_FRAME + 1];
            for (int i = 0; i < motionIcons.length; i++) motionIcons[i] = powerPathIcon(i / (float) LAST_ICON_FRAME);
        }
        int destination = enabled ? LAST_ICON_FRAME : 0;
        if (!ValueAnimator.areAnimatorsEnabled()) {
            iconFrame = destination;
            Tile tile = getQsTile();
            if (tile != null) { tile.setIcon(motionIcons[destination]); tile.updateTile(); }
            return;
        }
        iconMotion = ValueAnimator.ofInt(iconFrame, destination);
        iconMotion.setDuration(enabled ? 320 : 220);
        iconMotion.setInterpolator(new DecelerateInterpolator(1.5f));
        iconMotion.addUpdateListener(animation -> {
            if (!listening) return;
            int frame = (Integer) animation.getAnimatedValue();
            if (frame == iconFrame) return;
            iconFrame = frame;
            Tile tile = getQsTile();
            if (tile != null) { tile.setIcon(motionIcons[frame]); tile.updateTile(); }
        });
        iconMotion.start();
    }

    private static Icon powerPathIcon(float flow) {
        // Same 32-unit artwork as the app's _BypassPowerPathPainter.
        // NEESCHAL: animate the rail, never invent the charging state.
        Bitmap bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888);
        // 96 px at 640 dpi has the same intrinsic 24 dp as the resting vector.
        bitmap.setDensity(640);
        Canvas canvas = new Canvas(bitmap); canvas.scale(3, 3);
        Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        stroke.setColor(Color.WHITE); stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(1.8f); stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeJoin(Paint.Join.ROUND);
        canvas.drawLine(4, 7, 4, 10, stroke); canvas.drawLine(8, 7, 8, 10, stroke);
        canvas.drawRoundRect(new RectF(2, 10, 10, 17), 2, 2, stroke);
        Path rail = new Path(); rail.moveTo(6, 17); rail.lineTo(6, 20);
        rail.quadTo(6, 22, 8, 22); rail.lineTo(14, 22);
        rail.quadTo(16, 22, 16, 20); rail.lineTo(16, 13); rail.lineTo(21, 13);
        canvas.drawPath(rail, stroke);
        canvas.drawRoundRect(new RectF(21, 8, 30, 18), 2, 2, stroke);
        for (float x : new float[] {24, 27}) {
            canvas.drawLine(x, 5.5f, x, 8, stroke); canvas.drawLine(x, 18, x, 20.5f, stroke);
        }
        Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG); fill.setColor(Color.WHITE);
        canvas.drawRect(24, 11, 27, 15, fill);
        stroke.setStrokeWidth(1.4f); stroke.setAlpha(Math.round(255 * (0.55f - flow * 0.25f)));
        canvas.drawRoundRect(new RectF(20, 25, 30, 30), 1, 1, stroke);
        canvas.drawLine(18.5f, 26.5f, 18.5f, 28.5f, stroke);
        canvas.drawLine(17, 23.5f, 20, 23.5f, stroke);
        if (flow > 0) { fill.setAlpha(Math.round(255 * flow)); canvas.drawCircle(16 + 3 * flow, 13, 2, fill); }
        return Icon.createWithBitmap(bitmap);
    }
}
