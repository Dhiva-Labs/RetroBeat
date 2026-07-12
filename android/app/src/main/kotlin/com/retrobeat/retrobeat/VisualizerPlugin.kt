package com.retrobeat.retrobeat

import android.media.audiofx.Visualizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * Streams frequency magnitudes from the audio that is actually playing, using
 * android.media.audiofx.Visualizer attached to just_audio's audio session.
 *
 * This is the opt-in half of the visualiser. It is only ever started when the
 * user turns on "audio-reactive" in Settings, because the platform API requires
 * the RECORD_AUDIO permission — asking for that unprompted, in a music player,
 * looks exactly like spyware.
 */
class VisualizerPlugin(messenger: BinaryMessenger) : EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "retrobeat/visualizer"

        /** How many bars the UI draws. */
        const val BAND_COUNT = 24

        /** How many points the oscilloscope trace draws. */
        const val WAVE_POINTS = 96
    }

    private var visualizer: Visualizer? = null

    /**
     * The most recent waveform. The FFT and the waveform arrive on separate
     * callbacks; rather than emit twice per frame, the waveform is held and sent
     * alongside the next FFT so the UI gets one coherent frame.
     */
    private var latestWave: DoubleArray = DoubleArray(WAVE_POINTS)

    private val channel = EventChannel(messenger, CHANNEL).apply {
        setStreamHandler(this@VisualizerPlugin)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sessionId = (arguments as? Map<*, *>)?.get("sessionId") as? Int
        if (events == null) return

        if (sessionId == null || sessionId == 0) {
            events.error("no_session", "No audio session to attach to yet.", null)
            return
        }

        try {
            visualizer = Visualizer(sessionId).apply {
                // The smallest capture size keeps the FFT cheap; we only need a
                // couple of dozen bars, not a spectrogram.
                captureSize = Visualizer.getCaptureSizeRange()[0]
                setDataCaptureListener(
                    object : Visualizer.OnDataCaptureListener {
                        override fun onWaveFormDataCapture(
                            v: Visualizer?, waveform: ByteArray?, rate: Int,
                        ) {
                            if (waveform != null) latestWave = toWave(waveform)
                        }

                        override fun onFftDataCapture(
                            v: Visualizer?, fft: ByteArray?, rate: Int,
                        ) {
                            if (fft == null) return
                            events.success(
                                mapOf(
                                    "bands" to toBands(fft),
                                    "wave" to latestWave,
                                ),
                            )
                        }
                    },
                    // Half the maximum rate is plenty for 60fps and costs less
                    // battery.
                    Visualizer.getMaxCaptureRate() / 2,
                    true, // waveform: the oscilloscope styles need it
                    true, // fft: the bar styles need it
                )
                enabled = true
            }
        } catch (e: Throwable) {
            // Most commonly: RECORD_AUDIO not granted, or the device refuses to
            // attach a Visualizer to this session.
            release()
            events.error("visualizer_failed", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) = release()

    private fun release() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Throwable) {
            // Already gone; nothing to do.
        }
        visualizer = null
    }

    fun dispose() {
        release()
        channel.setStreamHandler(null)
    }

    /**
     * Fold the raw FFT into [BAND_COUNT] normalised magnitudes (0..1).
     *
     * The FFT arrives as interleaved real/imaginary pairs. Magnitudes are
     * converted to decibels because loudness is logarithmic — a linear scale
     * leaves the bars flat and lifeless for everything but the bass.
     */
    private fun toBands(fft: ByteArray): DoubleArray {
        val bins = fft.size / 2
        val bands = DoubleArray(BAND_COUNT)
        val perBand = max(1, bins / BAND_COUNT)

        for (band in 0 until BAND_COUNT) {
            var peak = 0.0
            val start = band * perBand
            val end = min(start + perBand, bins)

            for (i in start until end) {
                val real = fft[i * 2].toDouble()
                val imaginary = fft[i * 2 + 1].toDouble()
                peak = max(peak, hypot(real, imaginary))
            }

            // ~0..1 across a 60 dB window above the noise floor.
            val db = if (peak > 0) 20 * log10(peak) else 0.0
            bands[band] = (db / 60.0).coerceIn(0.0, 1.0)
        }
        return bands
    }

    /**
     * Downsample the PCM waveform to [WAVE_POINTS] values in -1..1, for the
     * oscilloscope trace.
     *
     * Waveform bytes are unsigned 8-bit centred on 128, but Kotlin's Byte is
     * signed — hence the `and 0xFF` before re-centring.
     */
    private fun toWave(waveform: ByteArray): DoubleArray {
        if (waveform.isEmpty()) return DoubleArray(WAVE_POINTS)

        val wave = DoubleArray(WAVE_POINTS)
        val step = waveform.size.toDouble() / WAVE_POINTS

        for (i in 0 until WAVE_POINTS) {
            val sample = waveform[(i * step).toInt().coerceIn(0, waveform.size - 1)]
            wave[i] = ((sample.toInt() and 0xFF) - 128) / 128.0
        }
        return wave
    }
}
