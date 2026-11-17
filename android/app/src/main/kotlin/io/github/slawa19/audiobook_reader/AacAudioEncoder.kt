package io.github.slawa19.audiobook_reader

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import java.io.File
import java.io.IOException

/** The system AAC-LC in an M4A container. */
object AacAudioEncoder {
    // Mono 24 kHz, speech: 48 kbit/s leaves a quality margin while taking about 22 MB/hour.
    // The value is part of the Dart formatId; when it changes, the fingerprints change too.
    const val SPEECH_BIT_RATE = 48_000
    private const val FRAME_SAMPLES = 1024
    private const val WAIT_US = 10_000L
    // No progress is a codec error, not an endless wait in the queue.
    private const val STALL_MS = 30_000L

    fun encode(pcmPath: String, outputPath: String, sampleRate: Int) {
        val input = File(pcmPath)
        val output = File(outputPath)
        require(input.canonicalPath != output.canonicalPath) { "Input and output are the same file" }
        var codec: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var complete = false
        try {
            val bytes = input.length()
            require(input.isFile && bytes > 0 && bytes % 2 == 0L && sampleRate > 0) {
                "Non-empty mono 16-bit PCM with a positive sample rate is expected"
            }
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, SPEECH_BIT_RATE)
                setInteger(MediaFormat.KEY_PCM_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAME_SAMPLES * 2)
            }
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val writer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            encoder.start()
            var track = -1
            var submitted = 0L
            var inputEnded = false
            var outputEnded = false
            var frames = 0L
            var lastProgress = SystemClock.elapsedRealtime()
            val info = MediaCodec.BufferInfo()
            val chunk = ByteArray(FRAME_SAMPLES * 2)
            input.inputStream().use { source ->
                while (!outputEnded) {
                    if (SystemClock.elapsedRealtime() - lastProgress > STALL_MS) {
                        throw IOException("The AAC encoder is not responding")
                    }
                    if (!inputEnded) {
                        val index = encoder.dequeueInputBuffer(WAIT_US)
                        if (index >= 0) {
                            val buffer = checkNotNull(encoder.getInputBuffer(index))
                            buffer.clear()
                            val count = minOf(chunk.size.toLong(), bytes - submitted, buffer.remaining().toLong()).toInt()
                            require(count % 2 == 0) { "Odd PCM buffer size" }
                            var read = 0
                            while (read < count) {
                                val n = source.read(chunk, read, count - read)
                                if (n < 0) throw IOException("PCM ended earlier than expected")
                                read += n
                            }
                            buffer.put(chunk, 0, count)
                            inputEnded = count == 0
                            // Time from the number of samples, without accumulating rounding error.
                            encoder.queueInputBuffer(index, 0, count, submitted / 2 * 1_000_000 / sampleRate,
                                if (inputEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                            submitted += count
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                    }
                    when (val index = encoder.dequeueOutputBuffer(info, WAIT_US)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(track == -1) { "The AAC format changed twice" }
                            val encodedFormat = encoder.outputFormat
                            track = writer.addTrack(encodedFormat)
                            writer.start()
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                        else -> if (index >= 0) {
                            val ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            try {
                                val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                                if (!config && info.size > 0) {
                                    check(track >= 0) { "AAC output arrived before the format" }
                                    val buffer = checkNotNull(encoder.getOutputBuffer(index))
                                    buffer.position(info.offset)
                                    buffer.limit(info.offset + info.size)
                                    // One AAC-LC output buffer is one frame. The input PTS do not
                                    // determine the duration of the tail after the codec is drained.
                                    info.presentationTimeUs = frames * FRAME_SAMPLES * 1_000_000 / sampleRate
                                    info.flags = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv()
                                    writer.writeSampleData(track, buffer, info)
                                    frames++
                                }
                            } finally {
                                outputEnded = ended
                                encoder.releaseOutputBuffer(index, false)
                            }
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
            check(track >= 0 && frames > 0) { "Empty AAC output" }
            writer.stop()
            writer.release()
            muxer = null
            encoder.stop()
            encoder.release()
            codec = null
            complete = true
        } finally {
            runCatching { codec?.release() }
            runCatching { muxer?.release() }
            if (!complete) output.delete()
        }
    }
}
